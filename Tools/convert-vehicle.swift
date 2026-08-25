#!/usr/bin/env swift
// Converts a Kenney OBJ model to .usdc for RealityKit.
// Usage: swift Tools/convert-vehicle.swift <input.obj> <output.usdc>
// Kenney kits are CC0 (kenney.nl) — thank you, Kenney.

import Foundation
import ModelIO

let args = CommandLine.arguments
guard args.count == 3 else {
    print("usage: convert-vehicle.swift <input.obj> <output.usdc>")
    exit(1)
}
let input = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[2])

let asset = MDLAsset(url: input)
asset.loadTextures()
do {
    try asset.export(to: output)
    print("wrote \(output.path)")
} catch {
    print("export failed: \(error)")
    exit(1)
}
