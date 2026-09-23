# Riggle

[![Gem version](https://badge.fury.io/rb/riggle.svg)](https://rubygems.org/gems/riggle)
[![Downloads](https://img.shields.io/gem/dt/riggle?label=downloads)](https://rubygems.org/gems/riggle)
[![CI](https://github.com/rbgfx/riggle/actions/workflows/main.yml/badge.svg)](https://github.com/rbgfx/riggle/actions/workflows/main.yml)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D3.1-CC342D?logo=ruby&logoColor=white)](https://www.ruby-lang.org/)
[![License](https://img.shields.io/badge/license-MIT-750014.svg)](LICENSE.txt)

> OBJ and glTF loading with CPU skinning for Ruby graphics.

Riggle turns common 3D asset files into small Ruby scene objects: meshes,
primitives, nodes, materials, animation channels, and skinning data.

**[Features](#features) · [Installation](#installation) · [Quick start](#quick-start) · [Development](#development)**

## Features

- OBJ loading with fan triangulation and negative indices.
- glTF JSON and GLB loading, including data URI buffers and accessors.
- Node transforms, materials, animation channels, and scene traversal.
- Linear blend skinning (LBS) and dual quaternion skinning (DQS).
- An optional RBGL adapter for vertex and index buffers.
- Defaults for missing normals, UVs, and colors when adapting to RBGL.

## Installation

Add Riggle to your Gemfile:

~~~ruby
gem "riggle"
~~~

Then run:

~~~sh
bundle install
~~~

Or install the released gem:

~~~sh
gem install riggle
~~~

## Quick start

~~~ruby
require "riggle"

scene = Riggle.load("model.obj", normals: :smooth)
primitive = scene.meshes.first.primitives.first
puts primitive.positions.length
~~~

When RBGL is available, convert a primitive with:

~~~ruby
vertex_buffer, index_buffer = primitive.to_rbgl
~~~

Pass an <code>RBGL::Engine::VertexLayout</code> to select an explicit layout.

## Development

~~~sh
bundle install
bundle exec rake verify
~~~

## License

[MIT](LICENSE.txt)
