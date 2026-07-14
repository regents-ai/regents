export const backgroundManifest = {
  home: "/images/backgrounds/home.svg",
  regents_labs: "/images/backgrounds/regents_labs.svg",
  formation: "/images/backgrounds/formation.svg",
  regent_record: "/images/backgrounds/regent_record.svg",
  techtree_overview: "/images/backgrounds/techtree_overview.svg",
  techtree_node: "/images/backgrounds/techtree_node.svg",
  techtree_tree: "/images/backgrounds/techtree_tree.svg",
  autolaunch: "/images/backgrounds/autolaunch.svg",
} as const

export type BackgroundSlot = keyof typeof backgroundManifest

export const isBackgroundSlot = (slot: string): slot is BackgroundSlot =>
  Object.prototype.hasOwnProperty.call(backgroundManifest, slot)
