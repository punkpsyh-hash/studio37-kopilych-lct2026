# Third-party notices

This directory vendors **Three.js 0.160.1** from the official npm package `three@0.160.1`.

Package integrity recorded by npm: `sha512-Bgl2wPJypDOZ1stAxwfWAcJ0WQf7QzlptsxkjYiURPz+n5k4RBDLsq+6f9Y75TYxn6aHLcWz+JNmwTOXWrQTBQ==` (`sha1 61fe2907312e8604b1f64187f58e047503847413`).

Included files:

- `vendor/three.module.min.js`
- `vendor/loaders/GLTFLoader.js`
- `vendor/utils/BufferGeometryUtils.js`
- `vendor/THREE-LICENSE.txt`

The two example modules only change their bare `three` import to a local relative import. The original MIT license is preserved verbatim in `vendor/THREE-LICENSE.txt`. Runtime loading uses only same-origin files served by the application's tokenized local loopback server; there are no CDN imports.
