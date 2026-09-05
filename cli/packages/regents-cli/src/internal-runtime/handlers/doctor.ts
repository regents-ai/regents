import { runDoctor, runFullDoctor, runScopedDoctor } from "../doctor/checkRunner.js";
import type { DoctorReport, DoctorRunFullParams, DoctorRunParams, DoctorRunScopedParams } from "../../internal-types/index.js";
import type { RuntimeContext } from "../runtime.js";

export async function handleDoctorRun(ctx: RuntimeContext, params?: DoctorRunParams): Promise<DoctorReport> {
    return runDoctor(params, { runtimeContext: ctx });
}

export async function handleDoctorRunScoped(
    ctx: RuntimeContext,
    params: DoctorRunScopedParams,
): Promise<DoctorReport> {
    return runScopedDoctor(params, { runtimeContext: ctx });
}

export async function handleDoctorRunFull(ctx: RuntimeContext, params?: DoctorRunFullParams): Promise<DoctorReport> {
    return runFullDoctor(params, { runtimeContext: ctx });
}
