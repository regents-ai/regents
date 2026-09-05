/**
 * Attach machine-readable `next_steps` hints to a JSON command payload.
 *
 * Several command families print a result object and want to surface the
 * follow-up commands an agent should run next. They all shaped the payload the
 * same way, so this is the single shared implementation.
 */
export const withNextSteps = <T>(
  payload: T,
  nextSteps: readonly string[],
): T & { next_steps: readonly string[] } =>
  ({
    ...(payload as Record<string, unknown>),
    next_steps: nextSteps,
  }) as T & { next_steps: readonly string[] };
