// GO's GTFS-realtime TripUpdates feed, read the way the app reads it (TT-131, D36). The decoder is a port of the app's
// `GTFSRealtimeFeed` and the mapping a port of `GTFSRealtimeLive`, so a notification and the timeline agree.

export interface StopTimeEvent {
  /** Seconds late; negative is early. */
  delay?: number;
  /** Epoch milliseconds. */
  time?: number;
}

export interface StopTimeUpdate {
  stopId?: string;
  arrival?: StopTimeEvent;
  departure?: StopTimeEvent;
  /** NO_DATA and UNSCHEDULED read as noData: no estimate for this stop. */
  relationship: 'scheduled' | 'skipped' | 'noData';
}

export interface TripUpdate {
  tripId: string;
  /** "20261109"; undefined when the feed leaves it out. */
  startDate?: string;
  /** CANCELED or DELETED. */
  cancelled: boolean;
  stopTimeUpdates: StopTimeUpdate[];
  /** Epoch milliseconds. */
  timestamp?: number;
  /** Trip-wide delay in seconds, used only when no stop says more. */
  delay?: number;
}

export interface Feed {
  /** When the producer wrote the feed, epoch milliseconds. */
  timestamp?: number;
  tripUpdates: TripUpdate[];
}

interface Field {
  number: number;
  wireType: number;
}

const utf8 = new TextDecoder();

/** Reads protobuf fields: varints, length-delimited values and nested messages. */
class ProtobufReader {
  bytes: Uint8Array;
  pos: number;
  end: number;

  constructor(bytes: Uint8Array, start = 0, end = bytes.length) {
    this.bytes = bytes;
    this.pos = start;
    this.end = end;
  }

  next(): Field | null {
    if (this.pos >= this.end) return null;
    const key = this.varint().lo;
    return { number: key >>> 3, wireType: key & 7 };
  }

  /** A varint as its low and high 32 bits; int32 values travel as ten-byte two's complement. */
  varint(): { lo: number; hi: number } {
    let lo = 0;
    let hi = 0;
    for (let shift = 0; this.pos < this.end && shift < 70; shift += 7) {
      const byte = this.bytes[this.pos++];
      if (shift < 28) lo |= (byte & 0x7f) << shift;
      else if (shift === 28) {
        lo |= (byte & 0x0f) << 28;
        hi |= (byte & 0x7f) >> 4;
      } else hi |= (byte & 0x7f) << (shift - 32);
      if ((byte & 0x80) === 0) return { lo: lo >>> 0, hi: hi >>> 0 };
    }
    throw new Error('Truncated protobuf');
  }

  uint(): number {
    const { lo, hi } = this.varint();
    return hi * 2 ** 32 + lo;
  }

  int32(): number {
    return this.varint().lo | 0;
  }

  /** A 32-bit float (wire type 5), as GTFS-realtime positions travel. */
  float(): number {
    if (this.end - this.pos < 4) throw new Error('Truncated protobuf');
    const value = new DataView(this.bytes.buffer, this.bytes.byteOffset + this.pos, 4).getFloat32(0, true);
    this.pos += 4;
    return value;
  }

  message(): ProtobufReader {
    const [start, end] = this.lengthDelimited();
    return new ProtobufReader(this.bytes, start, end);
  }

  string(): string {
    const [start, end] = this.lengthDelimited();
    return utf8.decode(this.bytes.subarray(start, end));
  }

  skip(field: Field): void {
    switch (field.wireType) {
      case 0:
        this.varint();
        break;
      case 1:
        this.advance(8);
        break;
      case 2:
        this.lengthDelimited();
        break;
      case 5:
        this.advance(4);
        break;
      default:
        throw new Error(`Unsupported protobuf wire type ${field.wireType}`);
    }
  }

  private lengthDelimited(): [number, number] {
    const length = this.uint();
    if (length > this.end - this.pos) throw new Error('Truncated protobuf');
    const start = this.pos;
    this.pos += length;
    return [start, this.pos];
  }

  private advance(count: number): void {
    if (this.end - this.pos < count) throw new Error('Truncated protobuf');
    this.pos += count;
  }
}

/** POSIX seconds to epoch milliseconds; 0 means unset. */
function instant(seconds: number): number | undefined {
  return seconds > 0 ? seconds * 1000 : undefined;
}

/**
 * Decodes a `FeedMessage`. Fields the server does not read are skipped, and with `trips` so is the rest of every other
 * trip's update, which keeps a minute cycle inside the Workers Free plan's 10 ms of CPU (D43).
 */
export function decodeFeed(bytes: Uint8Array, trips?: ReadonlySet<string>): Feed {
  const feed: Feed = { tripUpdates: [] };
  const message = new ProtobufReader(bytes);
  for (let field = message.next(); field; field = message.next()) {
    if (field.number === 1 && field.wireType === 2) {
      const header = message.message();
      for (let f = header.next(); f; f = header.next()) {
        if (f.number === 3 && f.wireType === 0) feed.timestamp = instant(header.uint());
        else header.skip(f);
      }
    } else if (field.number === 2 && field.wireType === 2) {
      const update = entity(message.message(), trips);
      if (update) feed.tripUpdates.push(update);
    } else message.skip(field);
  }
  return feed;
}

function entity(reader: ProtobufReader, trips?: ReadonlySet<string>): TripUpdate | null {
  let update: TripUpdate | null = null;
  let deleted = false;
  for (let field = reader.next(); field; field = reader.next()) {
    if (field.number === 2 && field.wireType === 0) deleted = reader.varint().lo !== 0;
    else if (field.number === 3 && field.wireType === 2) update = tripUpdate(reader.message(), trips);
    else reader.skip(field);
  }
  return deleted ? null : update;
}

function tripUpdate(reader: ProtobufReader, trips?: ReadonlySet<string>): TripUpdate | null {
  const update: TripUpdate = { tripId: '', cancelled: false, stopTimeUpdates: [] };
  for (let field = reader.next(); field; field = reader.next()) {
    if (field.number === 1 && field.wireType === 2) {
      const trip = reader.message();
      for (let f = trip.next(); f; f = trip.next()) {
        if (f.number === 1 && f.wireType === 2) update.tripId = trip.string();
        else if (f.number === 3 && f.wireType === 2) update.startDate = trip.string();
        else if (f.number === 4 && f.wireType === 0) {
          const relationship = trip.varint().lo;
          update.cancelled = relationship === 3 || relationship === 7; // CANCELED, DELETED
        } else trip.skip(f);
      }
      if (trips && !trips.has(update.tripId)) return null;
    } else if (field.number === 2 && field.wireType === 2) update.stopTimeUpdates.push(stopTimeUpdate(reader.message()));
    else if (field.number === 4 && field.wireType === 0) update.timestamp = instant(reader.uint());
    else if (field.number === 5 && field.wireType === 0) update.delay = reader.int32();
    else reader.skip(field);
  }
  return trips && !trips.has(update.tripId) ? null : update;
}

function stopTimeUpdate(reader: ProtobufReader): StopTimeUpdate {
  const update: StopTimeUpdate = { relationship: 'scheduled' };
  for (let field = reader.next(); field; field = reader.next()) {
    if (field.number === 2 && field.wireType === 2) update.arrival = event(reader.message());
    else if (field.number === 3 && field.wireType === 2) update.departure = event(reader.message());
    else if (field.number === 4 && field.wireType === 2) update.stopId = reader.string();
    else if (field.number === 5 && field.wireType === 0) {
      const relationship = reader.varint().lo;
      update.relationship = relationship === 0 ? 'scheduled' : relationship === 1 ? 'skipped' : 'noData';
    } else reader.skip(field);
  }
  return update;
}

function event(reader: ProtobufReader): StopTimeEvent {
  const result: StopTimeEvent = {};
  for (let field = reader.next(); field; field = reader.next()) {
    if (field.number === 1 && field.wireType === 0) result.delay = reader.int32();
    else if (field.number === 2 && field.wireType === 0) result.time = instant(reader.uint());
    else reader.skip(field);
  }
  return result;
}

/** One service day's trip updates by trip id (D9). An update dated another day is left out. */
export function tripUpdatesOn(feed: Feed, date: string): Map<string, TripUpdate> {
  const updates = new Map<string, TripUpdate>();
  for (const update of feed.tripUpdates) {
    if (update.startDate === undefined || update.startDate === date) updates.set(update.tripId, update);
  }
  return updates;
}

/** A trip's scheduled calls, in order, with the rider's origin and destination as positions in that list. */
export interface Call {
  stops: string[];
  /** Scheduled instants, epoch milliseconds. */
  arrivals: number[];
  departures: number[];
  from: number;
  to: number;
}

export type LiveStatus =
  | { kind: 'cancelled'; reportedAt: number }
  | { kind: 'skipped'; stop: 'origin' | 'destination'; reportedAt: number }
  | { kind: 'running'; delayMin: number; expected: number; reportedAt: number };

function eventLateness(event: StopTimeEvent | undefined, scheduled: number): number | null {
  if (!event) return null;
  if (event.time !== undefined) return (event.time - scheduled) / 1000;
  return event.delay ?? null;
}

/** Seconds late at a stop: the departure's time or delay, else the arrival's. Null for NO_DATA or no times. */
function lateness(update: StopTimeUpdate, scheduledArrival: number, scheduledDeparture: number): number | null {
  if (update.relationship !== 'scheduled') return null;
  return eventLateness(update.departure, scheduledDeparture) ?? eventLateness(update.arrival, scheduledArrival);
}

/**
 * What the feed says about the trip at the rider's origin, as the app's timeline reads it (D36). Null when it gives no
 * estimate for the departure, so the trip is Scheduled and no alert can rest on it.
 */
export function liveStatus(update: TripUpdate, call: Call, feedTime: number): LiveStatus | null {
  const reportedAt = update.timestamp ?? feedTime;
  if (update.cancelled) return { kind: 'cancelled', reportedAt };

  const positioned = update.stopTimeUpdates
    .map((stop) => ({ position: stop.stopId === undefined ? -1 : call.stops.indexOf(stop.stopId), stop }))
    .filter((entry) => entry.position >= 0);
  const origin = positioned.findLast((entry) => entry.position === call.from)?.stop;
  const destination = positioned.findLast((entry) => entry.position === call.to)?.stop;
  if (origin?.relationship === 'skipped') return { kind: 'skipped', stop: 'origin', reportedAt };
  if (destination?.relationship === 'skipped') return { kind: 'skipped', stop: 'destination', reportedAt };

  let delay: number | null;
  if (origin) {
    delay = lateness(origin, call.arrivals[call.from], call.departures[call.from]);
  } else {
    const earlier = positioned.findLast((entry) => entry.position < call.from && entry.stop.relationship !== 'skipped');
    delay = earlier
      ? lateness(earlier.stop, call.arrivals[earlier.position], call.departures[earlier.position])
      : (update.delay ?? null);
  }
  if (delay === null) return null;
  return {
    kind: 'running',
    delayMin: Math.trunc(delay / 60),
    expected: call.departures[call.from] + delay * 1000,
    reportedAt,
  };
}

/** One train from GO's VehiclePosition feed (TT-179), as `GET /v1/trains` serves it. */
export interface TrainPosition {
  tripId: string;
  /** "20261109"; undefined when the feed leaves it out. */
  startDate?: string;
  routeId?: string;
  latitude: number;
  longitude: number;
  /** STOPPED_AT a stop. */
  stopped: boolean;
  /** When the train reported this position, epoch milliseconds. */
  timestamp?: number;
}

/** Decodes a VehiclePosition `FeedMessage`: the trains with a trip and a position, the feed's own timestamp. */
export function decodeVehicles(bytes: Uint8Array): { timestamp?: number; trains: TrainPosition[] } {
  const message = new ProtobufReader(bytes);
  const result: { timestamp?: number; trains: TrainPosition[] } = { trains: [] };
  for (let field = message.next(); field; field = message.next()) {
    if (field.number === 1 && field.wireType === 2) {
      const header = message.message();
      for (let f = header.next(); f; f = header.next()) {
        if (f.number === 3 && f.wireType === 0) result.timestamp = instant(header.uint());
        else header.skip(f);
      }
    } else if (field.number === 2 && field.wireType === 2) {
      const entity = message.message();
      let deleted = false;
      let train: TrainPosition | null = null;
      for (let f = entity.next(); f; f = entity.next()) {
        if (f.number === 2 && f.wireType === 0) deleted = entity.varint().lo !== 0;
        else if (f.number === 4 && f.wireType === 2) train = vehiclePosition(entity.message());
        else entity.skip(f);
      }
      if (train && !deleted) result.trains.push(train);
    } else message.skip(field);
  }
  return result;
}

function vehiclePosition(reader: ProtobufReader): TrainPosition | null {
  let tripId: string | undefined;
  let startDate: string | undefined;
  let routeId: string | undefined;
  let latitude: number | undefined;
  let longitude: number | undefined;
  // IN_TRANSIT_TO is the default status.
  let status = 2;
  let timestamp: number | undefined;
  for (let field = reader.next(); field; field = reader.next()) {
    if (field.number === 1 && field.wireType === 2) {
      const trip = reader.message();
      for (let f = trip.next(); f; f = trip.next()) {
        if (f.number === 1 && f.wireType === 2) tripId = trip.string();
        else if (f.number === 3 && f.wireType === 2) startDate = trip.string();
        else if (f.number === 5 && f.wireType === 2) routeId = trip.string();
        else trip.skip(f);
      }
    } else if (field.number === 2 && field.wireType === 2) {
      const position = reader.message();
      for (let f = position.next(); f; f = position.next()) {
        if (f.number === 1 && f.wireType === 5) latitude = position.float();
        else if (f.number === 2 && f.wireType === 5) longitude = position.float();
        else position.skip(f);
      }
    } else if (field.number === 4 && field.wireType === 0) status = reader.varint().lo;
    else if (field.number === 5 && field.wireType === 0) timestamp = instant(reader.uint());
    else reader.skip(field);
  }
  if (!tripId || latitude === undefined || longitude === undefined) return null;
  return { tripId, startDate, routeId, latitude, longitude, stopped: status === 1, timestamp };
}
