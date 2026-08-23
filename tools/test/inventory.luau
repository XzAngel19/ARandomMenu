--!strict
--
-- Load the deliberate universal inventory snapshot.
--
-- Suites must compare against this count instead of a copied literal so the
-- next approved module addition changes one authority. The CLI has no file
-- API, so validate.sh emits `_inventory_snapshot.luau` from the JSON.

export type InventorySnapshot = {
    count: number,
    names: {string},
    paths: {string},
}

return require("./_inventory_snapshot") :: InventorySnapshot
