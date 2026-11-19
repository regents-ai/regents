import type {ProfileAction} from "./profile_client.mjs";
export type ProfileToolStatus = "unsupported" | "registering" | "ready" | "failed" | "stopped";
export interface ProfileToolInstallation {
  (): void;
  readonly status: ProfileToolStatus;
  readonly ready: Promise<ProfileToolStatus>;
  retry(): Promise<ProfileToolStatus>;
}
export function installProfileTools(profile: ProfileAction, win?: Window): ProfileToolInstallation;
