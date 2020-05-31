# WebP in TIP

## Chromium's WebM for Photos

[Google's WebP Homepage](http://developers.google.com/speed/webp)

## Integrating with TIP

__TIP__ uses _WebP_ by integrating in 2 separate ways.  For iOS, __TIP__ will link against a static framework already compiled by the WebP maintainers which works against all iOS architectures.  For Mac (a.k.a. Mac Catalyst), __TIP__ will build from source with the latest stable source from the _WebP_ repo (configured for macOS) to create a dynamic framework to embed in any Mac Catalyst targets.

## Why 2 separate ways?

### Mac (Catalyst)

Mac is now all Intel 64-bit, and thus only has 1 target architecture, making for a fast build.  Additionally, configuring WebP to build for Mac Catalyst (not just Mac) is a very big challenge, and it is simplest to just compile it with __TIP__ at this point.

The framework produced is `webp.framework` which is necessary to match the expected file hierarchy when building _WebP_ from source because the core headers are in the folder `webp` (which other files look for) and those same headers are used for the framework headers, making it necessary for the module name to match that folder name.  Changing the framework's module name to something else would required extensive modification to the source code, which we want to avoid.

### iOS

For iOS, there are 5 different architectures, which can be a lot to build over and over again for code-integration systems, so a precompiled binary that changes infrequently is ideal.

The precompiled framework comes as `WebP.framework` and so we will leave it as-is to avoid any unexpected problems from modifying a precompiled framework.

### In the end...

Having the 2 different frameworks named different is not ideal and, ultimately, it would be best if a Mac Catalyst binary could be produced by WebP maintainers.  But for now, we have full WebP support on iOS and macOS (via Catalyst) using 2 separate ways.
