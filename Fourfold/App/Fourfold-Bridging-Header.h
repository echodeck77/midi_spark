//  Fourfold-Bridging-Header.h
//  Ableton Link sync (2026-10-24 ferry): LinkKit's ABLLink.h is a pure-C API with no Swift module —
//  every LinkKit integration (including Ableton's own LinkHut sample) uses a bridging header for this
//  reason. Scoped to the Fourfold app target only (project.yml's SWIFT_OBJC_BRIDGING_HEADER setting).

// The vendored xcframework's slices put headers directly at Headers/ABLLink.h (no "LinkKit/"
// subfolder, no module map) — Xcode adds that Headers dir to the search path automatically when
// the framework is linked, so these import as plain names, not <LinkKit/...>.
#import <ABLLink.h>
#import <ABLLinkSettingsViewController.h>
