/**
 * Demand-side API for Tally Web App (Plan A)
 * Representing the public interface of `at_client_web`
 */

export interface AtClientOptions {
  atSign: string;
  namespace?: string;
  rootDomain?: string;
}

export interface AtKey {
  key: string;
  sharedBy?: string;
  sharedWith?: string;
  namespace?: string;
}

export interface AtEvent {
  operation: 'update' | 'delete';
  key: AtKey;
  value?: string | Uint8Array;
}

export class AtError extends Error {
  code: string;
  constructor(message: string, code: string);
}

export interface AtClientLike {
  /** Gets a string or Uint8Array value */
  get(key: AtKey): Promise<string | Uint8Array | null>;
  
  /** Puts a string or Uint8Array value */
  put(key: AtKey, value: string | Uint8Array): Promise<boolean>;
  
  /** Deletes a key */
  delete(key: AtKey): Promise<boolean>;
  
  /** Scans for keys matching the regex/filter */
  keys(filter?: string): Promise<AtKey[]>;
  
  /** Sends a notification */
  notify(key: AtKey, value: string): Promise<boolean>;
  
  /** 
   * Real-time event subscription via AsyncIterable.
   * Enables clean wrapping in React hooks (e.g. `useAtNotifications`).
   */
  subscribe(regex?: string): AsyncIterable<AtEvent>;
  
  /** Closes the connection and releases resources */
  close(): Promise<void>;
}

export declare class AtClient implements AtClientLike {
  static create(opts: AtClientOptions): Promise<AtClient>;
  static enroll(opts: AtClientOptions, appName: string, deviceName: string, otp: string): Promise<AtClient>;
  
  get(key: AtKey): Promise<string | Uint8Array | null>;
  put(key: AtKey, value: string | Uint8Array): Promise<boolean>;
  delete(key: AtKey): Promise<boolean>;
  keys(filter?: string): Promise<AtKey[]>;
  notify(key: AtKey, value: string): Promise<boolean>;
  subscribe(regex?: string): AsyncIterable<AtEvent>;
  close(): Promise<void>;
}
