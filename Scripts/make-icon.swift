#!/usr/bin/env swift
//
// Décline une image carrée dans les dix tailles d'icône attendues par macOS.
//
//     swift Scripts/make-icon.swift Logo-FacturX-Check.png
//
// Contrairement à iOS, macOS ne découpe pas l'icône : c'est à elle de porter
// sa forme. Une image à fond perdu ressort donc en carré dur au milieu des
// autres icônes du Dock. Le script applique la marge et le squircle attendus,
// d'après la grille d'Apple : sur un canevas de 1024, le corps de l'icône
// occupe 824 px centrés, aux coins arrondis en courbe continue.

import AppKit
import QuartzCore

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    print("usage : swift Scripts/make-icon.swift <logo-carré.png>")
    exit(2)
}

let source = URL(fileURLWithPath: arguments[1])
guard let image = NSImage(contentsOf: source),
      let artwork = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write(Data("image illisible : \(source.path)\n".utf8))
    exit(1)
}

guard artwork.width >= 1024, artwork.height >= 1024 else {
    FileHandle.standardError.write(Data("""
        l'image fait \(artwork.width)×\(artwork.height) px ; il en faut au moins 1024 \
        de côté pour la plus grande taille\n
        """.utf8))
    exit(1)
}

let destination = URL(fileURLWithPath: arguments[0])
    .deletingLastPathComponent()      // Scripts/
    .deletingLastPathComponent()      // racine du dépôt
    .appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset")
try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

/// Proportions de la grille d'icônes macOS, rapportées au canevas.
let bodyRatio: CGFloat = 824.0 / 1024.0
/// Le rayon des coins, rapporté au corps de l'icône.
let cornerRatio: CGFloat = 185.4 / 824.0

func icon(canvas: Int) -> CGImage? {
    let side = CGFloat(canvas)
    let body = (side * bodyRatio).rounded()
    let margin = ((side - body) / 2).rounded()

    guard let context = CGContext(data: nil, width: canvas, height: canvas,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }

    // `cornerCurve = .continuous` est le squircle d'Apple lui-même. Un simple
    // arc de cercle en approche la forme sans l'atteindre, et l'écart se voit
    // dès qu'on pose l'icône à côté d'une autre dans le Dock.
    let layer = CALayer()
    layer.frame = CGRect(x: margin, y: margin, width: body, height: body)
    layer.contents = artwork
    layer.contentsGravity = .resizeAspectFill
    layer.masksToBounds = true
    layer.cornerRadius = body * cornerRatio
    layer.cornerCurve = .continuous
    layer.render(in: context)

    return context.makeImage()
}

let slots: [(size: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1),
    (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)
]

var entries: [String] = []

for slot in slots {
    let canvas = slot.size * slot.scale
    guard let rendered = icon(canvas: canvas),
          let png = NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:])
    else {
        FileHandle.standardError.write(Data("rendu impossible en \(canvas) px\n".utf8))
        exit(1)
    }

    let name = "icon_\(slot.size)x\(slot.size)\(slot.scale == 2 ? "@2x" : "").png"
    try png.write(to: destination.appendingPathComponent(name))
    entries.append("""
        { "idiom" : "mac", "size" : "\(slot.size)x\(slot.size)", \
        "scale" : "\(slot.scale)x", "filename" : "\(name)" }
        """)
}

// On réécrit le catalogue d'un bloc : un fichier déclaré mais absent fait
// échouer la compilation des ressources.
let catalogue = """
{
  "images" : [
    \(entries.joined(separator: ",\n    "))
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

"""
try Data(catalogue.utf8).write(to: destination.appendingPathComponent("Contents.json"))

print("Icône déclinée en \(slots.count) tailles dans \(destination.path)")
