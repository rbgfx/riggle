# frozen_string_literal: true

RSpec.describe Riggle do
  it "has a version number" do
    expect(Riggle::VERSION).not_to be nil
  end

  it "loads OBJ faces and generates normals" do
    path = File.join(Dir.tmpdir, "riggle-test.obj")
    File.write(path, <<~OBJ)
      v 0 0 0
      v 1 0 0
      v 0 1 0
      f 1 2 3
    OBJ

    primitive = Riggle.load(path, normals: :smooth).meshes.first.primitives.first

    expect(primitive.indices).to eq([0, 1, 2])
    expect(primitive.normals.first.to_a).to eq([0.0, 0.0, 1.0])
  end

  it "reads a minimal glTF data URI" do
    values = [0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0].pack("e*")
    uri = "data:application/octet-stream;base64,#{[values].pack("m0")}"
    path = File.join(Dir.tmpdir, "riggle-test.gltf")
    File.write(path, JSON.generate("asset" => { "version" => "2.0" }, "buffers" => [{ "uri" => uri, "byteLength" => values.bytesize }], "bufferViews" => [{ "buffer" => 0, "byteOffset" => 0, "byteLength" => values.bytesize }], "accessors" => [{ "bufferView" => 0, "componentType" => 5126, "count" => 3, "type" => "VEC3" }], "meshes" => [{ "primitives" => [{ "attributes" => { "POSITION" => 0 } }] }]))

    expect(Riggle.load(path).meshes.first.primitives.first.positions.length).to eq(3)
  end

  it "rejects invalid glTF accessor and buffer view references" do
    bytes = [1.0, 2.0, 3.0].pack("e*")
    uri = "data:application/octet-stream;base64,#{[bytes].pack('m0')}"
    document = {
      "asset" => { "version" => "2.0" },
      "buffers" => [{ "uri" => uri, "byteLength" => bytes.bytesize }],
      "bufferViews" => [{ "buffer" => 0, "byteLength" => bytes.bytesize }],
      "accessors" => [{ "bufferView" => 0, "componentType" => 5126, "count" => 1, "type" => "VEC3" }],
      "meshes" => [{ "primitives" => [{ "attributes" => { "POSITION" => 0 } }] }]
    }
    Dir.mktmpdir do |directory|
      path = File.join(directory, "invalid-reference.gltf")
      [-1, 1].each do |index|
        document["meshes"][0]["primitives"][0]["attributes"]["POSITION"] = index
        File.write(path, JSON.generate(document))
        expect { Riggle.load(path) }.to raise_error(ArgumentError, /glTF accessor index/)
      end

      document["meshes"][0]["primitives"][0]["attributes"]["POSITION"] = 0
      [-1, 1].each do |index|
        document["accessors"][0]["bufferView"] = index
        File.write(path, JSON.generate(document))
        expect { Riggle.load(path) }.to raise_error(ArgumentError, /glTF buffer view index/)
      end
    end
  end

  it "rejects negative glTF scene references instead of using the last item" do
    bytes = [1.0, 2.0, 3.0].pack("e*")
    document = {
      "asset" => { "version" => "2.0" },
      "buffers" => [{ "uri" => "data:application/octet-stream;base64,#{[bytes].pack('m0')}", "byteLength" => bytes.bytesize }],
      "bufferViews" => [{ "buffer" => 0, "byteLength" => bytes.bytesize }],
      "accessors" => [{ "bufferView" => 0, "componentType" => 5126, "count" => 1, "type" => "VEC3" }],
      "images" => [{ "uri" => "data:image/png;base64," }],
      "textures" => [{ "source" => 0 }],
      "materials" => [{ "pbrMetallicRoughness" => { "baseColorTexture" => { "index" => 0 } } }],
      "meshes" => [{ "primitives" => [{ "attributes" => { "POSITION" => 0 }, "material" => 0 }] }],
      "nodes" => [{ "mesh" => 0, "skin" => 0, "children" => [] }],
      "skins" => [{ "joints" => [0], "skeleton" => 0 }]
    }
    animation = lambda do |json, sampler:, node:|
      json["animations"] = [{ "samplers" => [{ "input" => 0, "output" => 0 }],
                              "channels" => [{ "sampler" => sampler, "target" => { "node" => node, "path" => "translation" } }] }]
    end
    changes = [
      ["image", ->(json) { json["textures"][0]["source"] = -1 }],
      ["texture", ->(json) { json["materials"][0]["pbrMetallicRoughness"]["baseColorTexture"]["index"] = -1 }],
      ["material", ->(json) { json["meshes"][0]["primitives"][0]["material"] = -1 }],
      ["mesh", ->(json) { json["nodes"][0]["mesh"] = -1 }],
      ["node", ->(json) { json["nodes"][0]["children"] = [-1] }],
      ["node", ->(json) { json["skins"][0]["joints"] = [-1] }],
      ["node", ->(json) { json["skins"][0]["skeleton"] = -1 }],
      ["skin", ->(json) { json["nodes"][0]["skin"] = -1 }],
      ["animation sampler", ->(json) { animation.call(json, sampler: -1, node: 0) }],
      ["node", ->(json) { animation.call(json, sampler: 0, node: -1) }]
    ]
    Dir.mktmpdir do |directory|
      path = File.join(directory, "scene.gltf")
      File.write(path, JSON.generate(document))
      expect { Riggle.load(path, load_images: false) }.not_to raise_error
      changes.each do |kind, change|
        invalid = JSON.parse(JSON.generate(document))
        change.call(invalid)
        File.write(path, JSON.generate(invalid))
        expect { Riggle.load(path, load_images: false) }.to raise_error(ArgumentError, /glTF #{kind} index/)
      end
    end
  end

  it "rejects cyclic or ambiguous glTF node hierarchies" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "nodes.gltf")
      [[{ "children" => [0] }],
       [{ "children" => [1] }, { "children" => [0] }],
       [{ "children" => [2] }, { "children" => [2] }, {}]].each do |nodes|
        File.write(path, JSON.generate("asset" => { "version" => "2.0" }, "nodes" => nodes))
        expect { Riggle.load(path) }.to raise_error(ArgumentError, /glTF node hierarchy/)
      end
    end
  end

  it "rejects glTF accessors outside their buffer view" do
    bytes = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0].pack("e*")
    uri = "data:application/octet-stream;base64,#{[bytes].pack('m0')}"
    Dir.mktmpdir do |directory|
      path = File.join(directory, "invalid.gltf")
      document = {
        "asset" => { "version" => "2.0" },
        "buffers" => [{ "uri" => uri, "byteLength" => bytes.bytesize }],
        "bufferViews" => [{ "buffer" => 0, "byteOffset" => 12, "byteLength" => 12 }],
        "accessors" => [{ "bufferView" => 0, "byteOffset" => -12, "componentType" => 5126, "count" => 1, "type" => "VEC3" }],
        "meshes" => [{ "primitives" => [{ "attributes" => { "POSITION" => 0 } }] }]
      }
      [
        [12, 12, -12, /glTF accessor byte offset/],
        [-12, 12, 0, /glTF buffer view/],
        [12, 24, 0, /glTF buffer view/]
      ].each do |view_offset, view_length, accessor_offset, message|
        document["bufferViews"][0] = { "buffer" => 0, "byteOffset" => view_offset, "byteLength" => view_length }
        document["accessors"][0]["byteOffset"] = accessor_offset
        File.write(path, JSON.generate(document))
        expect { Riggle.load(path) }.to raise_error(ArgumentError, message)
      end
    end
  end

  it "rejects glTF image buffer views outside their buffer" do
    bytes = "image-data"
    document = {
      "asset" => { "version" => "2.0" },
      "buffers" => [{ "uri" => "data:application/octet-stream;base64,#{[bytes].pack('m0')}", "byteLength" => bytes.bytesize }],
      "bufferViews" => [{ "buffer" => 0, "byteOffset" => -4, "byteLength" => 4 }],
      "images" => [{ "bufferView" => 0 }], "meshes" => [], "nodes" => []
    }
    Dir.mktmpdir do |directory|
      path = File.join(directory, "invalid-image.gltf")
      File.write(path, JSON.generate(document))
      expect { Riggle.load(path, load_images: false) }.to raise_error(ArgumentError, /glTF buffer view/)
      document["bufferViews"][0]["byteOffset"] = 0
      document["images"][0]["bufferView"] = -1
      File.write(path, JSON.generate(document))
      expect { Riggle.load(path, load_images: false) }.to raise_error(ArgumentError, /glTF buffer view index/)
    end
  end

  it "applies sparse glTF accessor overrides" do
    bytes = ([0.0] * 9).pack("e*") + [1].pack("C") + [1.0, 2.0, 3.0].pack("e*")
    uri = "data:application/octet-stream;base64,#{[bytes].pack("m0")}"
    path = File.join(Dir.tmpdir, "riggle-sparse.gltf")
    File.write(path, JSON.generate(
      "asset" => { "version" => "2.0" },
      "buffers" => [{ "uri" => uri, "byteLength" => bytes.bytesize }],
      "bufferViews" => [
        { "buffer" => 0, "byteOffset" => 36, "byteLength" => 1 },
        { "buffer" => 0, "byteOffset" => 37, "byteLength" => 12 }
      ],
      "accessors" => [{
        "componentType" => 5126, "count" => 3, "type" => "VEC3",
        "sparse" => { "count" => 1, "indices" => { "bufferView" => 0, "componentType" => 5121 }, "values" => { "bufferView" => 1 } }
      }],
      "meshes" => [{ "primitives" => [{ "attributes" => { "POSITION" => 0 } }] }]
    ))

    positions = Riggle.load(path).meshes.first.primitives.first.positions
    expect(positions.map(&:to_a)).to eq([[0.0, 0.0, 0.0], [1.0, 2.0, 3.0], [0.0, 0.0, 0.0]])
  end

  it "rejects external glTF images outside the base directory" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "scene.gltf")
      File.write(path, JSON.generate("asset" => { "version" => "2.0" }, "images" => [{ "uri" => "../outside.png" }]))

      expect { Riggle.load(path) }.to raise_error(ArgumentError, /image escapes base_dir/)
    end
  end

  it "interpolates animation channels and normalizes rotations" do
    channel = Riggle::Channel.new(node_index: 0, path: :translation, times: [0.0, 1.0], values: [[0.0, 0.0, 0.0], [2.0, 0.0, 0.0]])
    animation = Riggle::Animation.new(name: "move", channels: [channel])

    expect(animation.sample(0.5)[0][:translation]).to eq([1.0, 0.0, 0.0])
  end

  it "uses spherical interpolation for rotations" do
    channel = Riggle::Channel.new(
      node_index: 0,
      path: :rotation,
      times: [0.0, 1.0],
      values: [[0.0, 0.0, 0.0, 1.0], [0.0, 0.0, Math.sin(Math::PI / 3), Math.cos(Math::PI / 3)]]
    )

    result = channel.sample(0.5)
    expect(result[0]).to be_within(1e-12).of(0.0)
    expect(result[1]).to be_within(1e-12).of(0.0)
    expect(result[2]).to be_within(1e-12).of(0.5)
    expect(result[3]).to be_within(1e-12).of(Math.cos(Math::PI / 6))
  end

  it "interpolates cubic spline channels" do
    channel = Riggle::Channel.new(
      node_index: 0,
      path: :translation,
      times: [0.0, 1.0],
      values: [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [2.0, 0.0, 0.0],
               [0.0, 0.0, 0.0], [2.0, 0.0, 0.0], [0.0, 0.0, 0.0]],
      interpolation: "CUBICSPLINE"
    )

    expect(channel.sample(0.5).first).to be_within(1e-10).of(1.25)
  end

  it "loads glTF animations, skins, and vertex skin attributes" do
    times = [0.0, 1.0].pack("e*")
    translations = [0.0, 0.0, 0.0, 2.0, 0.0, 0.0].pack("e*")
    inverse_bind = [1.0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1].pack("e*")
    buffers = [times, translations, inverse_bind]
    uris = buffers.map { |value| "data:application/octet-stream;base64,#{[value].pack("m0")}" }
    path = File.join(Dir.tmpdir, "riggle-animation.gltf")
    File.write(path, JSON.generate(
      "asset" => { "version" => "2.0" },
      "buffers" => buffers.each_with_index.map { |value, index| { "uri" => uris[index], "byteLength" => value.bytesize } },
      "bufferViews" => buffers.each_index.map { |index| { "buffer" => index, "byteLength" => buffers[index].bytesize } },
      "accessors" => [
        { "bufferView" => 0, "componentType" => 5126, "count" => 2, "type" => "SCALAR" },
        { "bufferView" => 1, "componentType" => 5126, "count" => 2, "type" => "VEC3" },
        { "bufferView" => 2, "componentType" => 5126, "count" => 1, "type" => "MAT4" }
      ],
      "nodes" => [{ "children" => [], "translation" => [0, 0, 0], "rotation" => [0, 0, 0, 1], "scale" => [1, 1, 1] }],
      "skins" => [{ "joints" => [0], "inverseBindMatrices" => 2, "skeleton" => 0 }],
      "animations" => [{ "name" => "move", "samplers" => [{ "input" => 0, "output" => 1 }], "channels" => [{ "sampler" => 0, "target" => { "node" => 0, "path" => "translation" } }] }]
    ))

    scene = Riggle.load(path)

    expect(scene.skins.first.inverse_bind_matrices.first.transform(Riggle::Vec3.new(x: 1, y: 2, z: 3)).to_a).to eq([1.0, 2.0, 3.0])
    expect(scene.animations.first.sample(0.5)[0][:translation]).to eq([1.0, 0.0, 0.0])
  end

  it "triangulates a quad without a degenerate triangle and keeps omitted UVs empty" do
    path = File.join(Dir.tmpdir, "riggle-quad.obj")
    File.write(path, <<~OBJ)
      v 0 0 0
      v 1 0 0
      v 1 1 0
      v 0 1 0
      vn 0 0 1
      f 1//1 2//1 3//1 4//1
    OBJ
    primitive = Riggle.load(path).meshes.first.primitives.first
    expect(primitive.indices).to eq([0, 1, 2, 0, 2, 3])
    expect(primitive.uvs).to be_nil
    expect(primitive.normals.map(&:to_a)).to eq([[0.0, 0.0, 1.0]] * 4)
  end

  it "applies sampled translations and loops at the animation duration" do
    node = Riggle::Node.new(children: [], translation: Riggle::Vec3.new(x: 0, y: 0, z: 0), rotation: Riggle::Quat.new(x: 0, y: 0, z: 0, w: 1), scale: Riggle::Vec3.new(x: 1, y: 1, z: 1))
    scene = Riggle::Scene.new(nodes: [node])
    channel = Riggle::Channel.new(node_index: 0, path: :translation, times: [0.0, 1.0], values: [[0.0, 0.0, 0.0], [2.0, 0.0, 0.0]])
    scene.apply_pose!(Riggle::Animation.new(name: "move", channels: [channel]).sample(1.5, loop: true))
    expect(scene.world_matrix(0).transform(Riggle::Vec3.new(x: 0, y: 0, z: 0)).to_a).to eq([1.0, 0.0, 0.0])
  end

  it "rejects invalid scene node indices" do
    node = Riggle::Node.new(children: [], translation: Riggle::Vec3.new(x: 0, y: 0, z: 0), rotation: Riggle::Quat.new(x: 0, y: 0, z: 0, w: 1), scale: Riggle::Vec3.new(x: 1, y: 1, z: 1))
    scene = Riggle::Scene.new(nodes: [node])

    [-1, 1].each do |index|
      expect { scene.world_matrix(index) }.to raise_error(ArgumentError, /node/)
      expect { scene.apply_pose!(index => { translation: [1, 2, 3] }) }.to raise_error(ArgumentError, /node/)
    end
    expect(node.translation.to_a).to eq([0, 0, 0])
  end

  it "transposes glTF column-major node matrices before transforming points" do
    path = File.join(Dir.tmpdir, "riggle-matrix.gltf")
    File.write(path, JSON.generate("asset" => { "version" => "2.0" }, "nodes" => [{ "matrix" => [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 3, 4, 5, 1] }]))
    origin = Riggle::Vec3.new(x: 0, y: 0, z: 0)
    expect(Riggle.load(path).world_matrix(0).transform(origin).to_a).to eq([3.0, 4.0, 5.0])
  end

  it "applies dual quaternion skinning to rigid translations" do
    node = Riggle::Node.new(children: [], translation: Riggle::Vec3.new(x: 2, y: 0, z: 0), rotation: Riggle::Quat.new(x: 0, y: 0, z: 0, w: 1), scale: Riggle::Vec3.new(x: 1, y: 1, z: 1))
    scene = Riggle::Scene.new(nodes: [node])
    primitive = Riggle::Primitive.new(positions: [Riggle::Vec3.new(x: 1, y: 0, z: 0)], joints: [[0]], weights: [[1.0]])
    skin = Riggle::Skin.new(joints: [0], inverse_bind_matrices: [Riggle::Mat4.identity])

    expect(Riggle::Skinning.apply(primitive, skin, scene, method: :dqs).first.to_a).to eq([3.0, 0.0, 0.0])
  end

  it "falls back to linear blend skinning for non rigid transforms" do
    node = Riggle::Node.new(children: [], translation: Riggle::Vec3.new(x: 0, y: 0, z: 0), rotation: Riggle::Quat.new(x: 0, y: 0, z: 0, w: 1), scale: Riggle::Vec3.new(x: 2, y: 1, z: 1))
    scene = Riggle::Scene.new(nodes: [node])
    primitive = Riggle::Primitive.new(positions: [Riggle::Vec3.new(x: 1, y: 0, z: 0)], joints: [[0]], weights: [[1.0]])
    skin = Riggle::Skin.new(joints: [0], inverse_bind_matrices: [Riggle::Mat4.identity])

    expect(Riggle::Skinning.apply(primitive, skin, scene, method: :dqs).first.to_a).to eq([2.0, 0.0, 0.0])
  end

  it "skins normals with inverse transpose and DQS rotation" do
    node = Riggle::Node.new(children: [], translation: Riggle::Vec3.new(x: 0, y: 0, z: 0), rotation: Riggle::Quat.new(x: 0, y: 0, z: 0, w: 1), scale: Riggle::Vec3.new(x: 2, y: 1, z: 1))
    scene = Riggle::Scene.new(nodes: [node])
    normal = Riggle::Vec3.new(x: 1, y: 1, z: 0).normalize
    primitive = Riggle::Primitive.new(positions: [Riggle::Vec3.new(x: 0, y: 0, z: 0)], normals: [normal], joints: [[0]], weights: [[1.0]])
    skin = Riggle::Skin.new(joints: [0], inverse_bind_matrices: [Riggle::Mat4.identity])

    transformed = Riggle::Skinning.apply_normals(primitive, skin, scene).first
    expect(transformed.x).to be_within(1e-6).of(1.0 / Math.sqrt(5))
    expect(transformed.y).to be_within(1e-6).of(2.0 / Math.sqrt(5))

    rotated_node = Riggle::Node.new(children: [], translation: Riggle::Vec3.new(x: 0, y: 0, z: 0), rotation: Riggle::Quat.new(x: 0, y: 0, z: Math.sqrt(0.5), w: Math.sqrt(0.5)), scale: Riggle::Vec3.new(x: 1, y: 1, z: 1))
    rotated_scene = Riggle::Scene.new(nodes: [rotated_node])
    rotated_primitive = Riggle::Primitive.new(positions: [Riggle::Vec3.new(x: 0, y: 0, z: 0)], normals: [Riggle::Vec3.new(x: 1, y: 0, z: 0)], joints: [[0]], weights: [[1.0]])
    rotated = Riggle::Skinning.apply_normals(rotated_primitive, skin, rotated_scene, method: :dqs).first
    expect(rotated.x).to be_within(1e-6).of(0.0)
    expect(rotated.y).to be_within(1e-6).of(1.0)
    expect(rotated.z).to be_within(1e-6).of(0.0)
  end

  it "converts primitives to RBGL buffers and fills missing attributes" do
    require "riggle/rbgl"
    primitive = Riggle::Primitive.new(
      positions: [Riggle::Vec3.new(x: 0, y: 0, z: 0), Riggle::Vec3.new(x: 1, y: 0, z: 0), Riggle::Vec3.new(x: 0, y: 1, z: 0)],
      indices: [0, 1, 2]
    )

    buffers = nil
    expect { buffers = primitive.to_rbgl(layout: :position_normal_uv) }.to output(/missing attributes/).to_stderr
    vertex_buffer, index_buffer = buffers

    expect(vertex_buffer.get_vertex(0)[:normal].to_a).to eq([0.0, 0.0, 1.0])
    expect(vertex_buffer.get_vertex(0)[:uv].to_a).to eq([0.0, 0.0])
    expect(index_buffer.indices).to eq([0, 1, 2])
  end
end
