/**
 * The page's one GPU device for its small pictures: every value card's panel,
 * and the glow behind the Overview hero's lab map, draw on it together.
 */
import {init} from "vgpu"

import {shareDevice} from "./shared_device"

export const pageDevice = shareDevice(() => init())
