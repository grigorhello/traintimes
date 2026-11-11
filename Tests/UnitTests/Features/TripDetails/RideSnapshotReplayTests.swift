import XCTest

// TEMPORARY, not for merging: each subclass runs every RideSnapshotTests test again against the same references, so one CI
// run plays the suite's sequence seven times. testPermissionLight fails in about a third of CI runs; seven plays should
// catch it and put the diagnostics line (which colours change) in the log.
final class RideSnapshotReplay1Tests: RideSnapshotTests {}
final class RideSnapshotReplay2Tests: RideSnapshotTests {}
final class RideSnapshotReplay3Tests: RideSnapshotTests {}
final class RideSnapshotReplay4Tests: RideSnapshotTests {}
final class RideSnapshotReplay5Tests: RideSnapshotTests {}
final class RideSnapshotReplay6Tests: RideSnapshotTests {}
