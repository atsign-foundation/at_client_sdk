// Compiled by `npm run typecheck` against dist/index.d.ts; it has no runtime.
import type * as pinned from './pinned/at-client.js';
import type * as impl from '../../dist/index.js';
import { AtClient } from '../../dist/index.js';

declare const client: impl.AtClient;

// An AtClient is the pinned AtClientLike.
export const like: pinned.AtClientLike = client;

// Its static side has the pinned create and enroll signatures.
export const statics: {
  create: typeof pinned.AtClient.create;
  enroll: typeof pinned.AtClient.enroll;
} = AtClient;

// The pinned data types and the exported ones are interchangeable where the
// pin says they flow.
export const optionsIn: impl.AtClientOptions = {} as pinned.AtClientOptions;
export const keyIn: impl.AtKey = {} as pinned.AtKey;
export const keyOut: pinned.AtKey = {} as impl.AtKey;
export const eventOut: pinned.AtEvent = {} as impl.AtEvent;
export const errorOut: Error & { code: string } = {} as impl.AtError;

// The pinned class is satisfied instance-side as well.
export const instance: pinned.AtClient = client;

// The recorded superset.
export const prf: Promise<boolean> = AtClient.prfSupported();
export const onboarded: Promise<impl.AtClient> = AtClient.onboard(
  { atSign: '@a', namespace: 'n', app: 'a', rpId: 'r', rpName: 'N' },
  { cram: 'c', deviceName: 'd' },
);
export const code: impl.AtErrorCode = 'bad_key';
