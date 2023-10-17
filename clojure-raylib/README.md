# raylib clojure playground

Just me playing with [raylib](https://www.raylib.com/) and clojure.

To run it you need [raylib-clj](https://github.com/rutenkolk/raylib-clj.git).
Checkout that repo, and run `lein uberjar`, update the jar location in deps.edn
in this repo. You might need to update the `cffi/load-library "path so raylib
shared library file"` in raylib-clj to get it to build.


* [Pong](./src/examples/pong.clj)
* [Asteroids](./src/examples/asteroids.clj)

Built with:

* Clojure 1.11
* Raylib `4.6-dev` (2023-10-17)
