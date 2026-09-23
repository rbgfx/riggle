<h1 align="center">Riggle</h1>

<p align="center">OBJ and glTF loading with CPU skinning for Ruby graphics.</p>

<p align="center">
  <a href="https://rubygems.org/gems/riggle"><img src="https://badge.fury.io/rb/riggle.svg" alt="Gem Version"></a>
  <a href="https://rubygems.org/gems/riggle"><img src="https://img.shields.io/gem/dt/riggle?label=downloads" alt="Downloads"></a>
  <a href="https://www.ruby-lang.org/"><img src="https://img.shields.io/badge/ruby-%3E%3D3.1-CC342D?logo=ruby&amp;logoColor=white" alt="Ruby Version"></a>
  <a href="LICENSE.txt"><img src="https://img.shields.io/badge/license-MIT-750014.svg" alt="License"></a>
</p>

[Features](#features) · [Installation](#installation) · [Quick Start](#quick-start)

***

Riggle turns common 3D asset files into small Ruby scene objects: meshes, primitives, nodes, materials, animation channels, and skinning data.

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

### Requirements

- Ruby 3.1 or newer.
- RBGL is optional and only needed when using the RBGL adapter.

## Quick Start

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

## Contributing

Bug reports and pull requests are welcome at [rbgfx/riggle](https://github.com/rbgfx/riggle).

## License

[MIT](LICENSE.txt)
