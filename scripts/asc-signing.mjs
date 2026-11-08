#!/usr/bin/env node
// App Store Connect API calls for the TestFlight workflow (TT-154, D47). Node 20 or later, no packages.
//
//   node scripts/asc-signing.mjs setup <dir>   creates an Apple Distribution certificate from <dir>/csr.pem and an
//                                              App Store profile for it; writes cert.cer, profile.mobileprovision
//                                              and state.json to <dir>
//   node scripts/asc-signing.mjs wait          waits until build $BUILD_NUMBER has finished processing
//   node scripts/asc-signing.mjs cleanup [dir] deletes the profile and revokes the certificate (ids from
//                                              <dir>/state.json, or $ASC_PROFILE_ID and $ASC_CERTIFICATE_ID)
//
// Needs an App Store Connect API key with the Admin role: ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_P8 (the .p8 contents).
// Each run makes its own certificate and revokes it once its build is processed, so no certificate is kept in secrets.
// Revoking does not affect builds already in TestFlight or the App Store, which Apple re-signs.
import { createPrivateKey, sign } from 'node:crypto'
import { appendFileSync, existsSync, readFileSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'

const BUNDLE_ID = 'ca.traintimes.TrainTimes'
const API = process.env.ASC_API_BASE ?? 'https://api.appstoreconnect.apple.com'

function env(name) {
  const value = process.env[name]?.trim()
  if (!value) throw new Error(`Missing ${name}. Add it under Settings › Secrets and variables › Actions.`)
  return value
}

function token() {
  const now = Math.floor(Date.now() / 1000)
  const part = (object) => Buffer.from(JSON.stringify(object)).toString('base64url')
  const input = `${part({ alg: 'ES256', kid: env('ASC_KEY_ID'), typ: 'JWT' })}.${part({
    iss: env('ASC_ISSUER_ID'), iat: now, exp: now + 15 * 60, aud: 'appstoreconnect-v1'
  })}`
  const key = createPrivateKey(env('ASC_KEY_P8').replace(/\\n/g, '\n'))
  return `${input}.${sign('sha256', Buffer.from(input), { key, dsaEncoding: 'ieee-p1363' }).toString('base64url')}`
}

async function api(method, path, body) {
  const response = await fetch(API + path, {
    method,
    headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/json' },
    body: body && JSON.stringify(body)
  })
  if (response.status === 204) return null
  const json = await response.json().catch(() => ({}))
  if (!response.ok) {
    const detail = (json.errors ?? []).map((e) => `${e.title ?? e.code}: ${e.detail ?? ''}`).join('; ')
    const error = new Error(`${method} ${path} → ${response.status} ${detail}`)
    error.status = response.status
    throw error
  }
  return json
}

function output(name, value) {
  if (process.env.GITHUB_OUTPUT) appendFileSync(process.env.GITHUB_OUTPUT, `${name}=${value}\n`)
}

async function setup(dir) {
  const statePath = join(dir, 'state.json')
  const state = {}
  const save = () => writeFileSync(statePath, JSON.stringify(state, null, 2))

  const certificate = await api('POST', '/v1/certificates', {
    data: { type: 'certificates', attributes: { certificateType: 'DISTRIBUTION', csrContent: readFileSync(join(dir, 'csr.pem'), 'utf8') } }
  })
  state.certificateId = certificate.data.id
  save()
  output('certificate', state.certificateId)
  writeFileSync(join(dir, 'cert.cer'), Buffer.from(certificate.data.attributes.certificateContent, 'base64'))
  console.log(`Created certificate ${state.certificateId} (${certificate.data.attributes.name})`)

  const bundles = await api('GET', `/v1/bundleIds?filter[identifier]=${BUNDLE_ID}&limit=200`)
  const bundle = bundles.data.find((b) => b.attributes.identifier === BUNDLE_ID)
  if (!bundle) throw new Error(`No App ID ${BUNDLE_ID} in this team`)

  const profile = await api('POST', '/v1/profiles', {
    data: {
      type: 'profiles',
      attributes: { name: `Train Times TestFlight ${Date.now()}`, profileType: 'IOS_APP_STORE' },
      relationships: {
        bundleId: { data: { type: 'bundleIds', id: bundle.id } },
        certificates: { data: [{ type: 'certificates', id: state.certificateId }] }
      }
    }
  })
  Object.assign(state, { profileId: profile.data.id, profileName: profile.data.attributes.name, profileUuid: profile.data.attributes.uuid })
  save()
  output('profile', state.profileId)
  writeFileSync(join(dir, 'profile.mobileprovision'), Buffer.from(profile.data.attributes.profileContent, 'base64'))
  console.log(`Created profile ${state.profileName}`)
}

async function wait() {
  const build = env('BUILD_NUMBER')
  const apps = await api('GET', `/v1/apps?filter[bundleId]=${BUNDLE_ID}`)
  const app = apps.data.find((a) => a.attributes.bundleId === BUNDLE_ID)
  if (!app) throw new Error(`No App Store Connect app for ${BUNDLE_ID}`)
  const deadline = Date.now() + 50 * 60 * 1000
  let last = ''
  while (Date.now() < deadline) {
    const builds = await api('GET', `/v1/builds?filter[app]=${app.id}&filter[version]=${build}&limit=1`)
    const state = builds.data[0]?.attributes.processingState ?? 'not visible yet'
    if (state !== last) console.log(`Build ${build}: ${state}`)
    last = state
    if (state === 'VALID') return console.log(`Build ${build} is processed and ready in TestFlight.`)
    if (state === 'FAILED' || state === 'INVALID') throw new Error(`Build ${build} is ${state}; Apple emails the reason.`)
    await new Promise((resolve) => setTimeout(resolve, 60_000))
  }
  throw new Error(`Build ${build} was still processing after 50 minutes; check TestFlight.`)
}

async function cleanup(dir) {
  const state = dir && existsSync(join(dir, 'state.json')) ? JSON.parse(readFileSync(join(dir, 'state.json'), 'utf8')) : {}
  const profileId = state.profileId ?? process.env.ASC_PROFILE_ID
  const certificateId = state.certificateId ?? process.env.ASC_CERTIFICATE_ID
  for (const [path, label] of [[profileId && `/v1/profiles/${profileId}`, 'profile'], [certificateId && `/v1/certificates/${certificateId}`, 'certificate']]) {
    if (!path) continue
    try {
      await api('DELETE', path)
      console.log(`Removed the ${label}`)
    } catch (error) {
      if (error.status !== 404 && error.status !== 409) throw error
      console.log(`The ${label} was already gone (${error.status})`)
    }
  }
}

const [command, dir] = process.argv.slice(2)
const commands = { setup: () => setup(dir), wait, cleanup: () => cleanup(dir) }
if (!commands[command]) {
  console.error('Usage: asc-signing.mjs setup <dir> | wait | cleanup [dir]')
  process.exit(2)
}
commands[command]().catch((error) => {
  console.error(`::error::${error.message}`)
  process.exit(1)
})
