# frozen_string_literal: true

require "json"

require_relative "riggle/version"

module Riggle
  class Error < StandardError; end
  class UnsupportedError < ArgumentError; end

  Vec2 = Struct.new(:x, :y, keyword_init: true) do
    def to_a = [x, y]
  end
  Vec3 = Struct.new(:x, :y, :z, keyword_init: true) do
    def to_a = [x, y, z]
    def +(other) = Vec3.new(x: x + other.x, y: y + other.y, z: z + other.z)
    def -(other) = Vec3.new(x: x - other.x, y: y - other.y, z: z - other.z)
    def *(scalar) = Vec3.new(x: x * scalar, y: y * scalar, z: z * scalar)
    def dot(other) = x * other.x + y * other.y + z * other.z
    def cross(other) = Vec3.new(x: y * other.z - z * other.y, y: z * other.x - x * other.z, z: x * other.y - y * other.x)
    def normalize
      length = Math.sqrt(dot(self))
      length.zero? ? self : self * (1.0 / length)
    end
  end
  Color = Struct.new(:r, :g, :b, :a, keyword_init: true) do
    def to_a = [r, g, b, a]
  end
  Quat = Struct.new(:x, :y, :z, :w, keyword_init: true) do
    def to_a = [x, y, z, w]
    def normalize
      length = Math.sqrt(x * x + y * y + z * z + w * w)
      length.zero? ? self : Quat.new(x: x / length, y: y / length, z: z / length, w: w / length)
    end

    def self.slerp(first, second, amount)
      left = first.normalize
      right = second.normalize
      dot = left.to_a.zip(right.to_a).sum { |a, b| a * b }
      if dot.negative?
        right = new(x: -right.x, y: -right.y, z: -right.z, w: -right.w)
        dot = -dot
      end
      if dot > 0.9995
        return new(
          x: left.x + (right.x - left.x) * amount,
          y: left.y + (right.y - left.y) * amount,
          z: left.z + (right.z - left.z) * amount,
          w: left.w + (right.w - left.w) * amount
        ).normalize
      end

      angle = Math.acos(dot.clamp(-1.0, 1.0))
      scale = Math.sin((1.0 - amount) * angle) / Math.sin(angle)
      other_scale = Math.sin(amount * angle) / Math.sin(angle)
      new(
        x: left.x * scale + right.x * other_scale,
        y: left.y * scale + right.y * other_scale,
        z: left.z * scale + right.z * other_scale,
        w: left.w * scale + right.w * other_scale
      )
    end
  end

  class Mat4
    attr_reader :values

    def initialize(values = nil)
      @values = (values || identity_values).map(&:to_f)
      raise ArgumentError, "Mat4 needs 16 values" unless @values.length == 16
    end

    def [](row, column)
      @values[row * 4 + column]
    end

    def *(other)
      Mat4.new(Array.new(16) { |index| row = index / 4; column = index % 4; (0...4).sum { |k| self[row, k] * other[k, column] } })
    end

    def transform(point)
      values = [point.x, point.y, point.z, 1.0]
      result = (0...4).map { |row| (0...4).sum { |column| self[row, column] * values[column] } }
      Vec3.new(x: result[0] / result[3], y: result[1] / result[3], z: result[2] / result[3])
    end

    def self.trs(translation, rotation, scale)
      x, y, z, w = rotation.to_a
      sx, sy, sz = scale.to_a
      Mat4.new([
        (1 - 2 * (y * y + z * z)) * sx, (2 * (x * y - z * w)) * sy, (2 * (x * z + y * w)) * sz, translation.x,
        (2 * (x * y + z * w)) * sx, (1 - 2 * (x * x + z * z)) * sy, (2 * (y * z - x * w)) * sz, translation.y,
        (2 * (x * z - y * w)) * sx, (2 * (y * z + x * w)) * sy, (1 - 2 * (x * x + y * y)) * sz, translation.z,
        0, 0, 0, 1
      ])
    end

    def self.identity = new

    private

    def identity_values = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
  end

  Material = Struct.new(:name, :base_color_factor, :base_color_texture, :emissive, :alpha_mode, keyword_init: true)
  TextureRef = Struct.new(:path, :image, keyword_init: true)
  Primitive = Struct.new(:positions, :normals, :uvs, :colors, :indices, :material, :joints, :weights, keyword_init: true) do
    def to_rbgl(**options)
      require_relative "riggle/rbgl"
      Riggle::RBGL.to_rbgl(self, **options)
    end
  end
  Mesh = Struct.new(:name, :primitives, keyword_init: true)
  Node = Struct.new(:name, :children, :mesh, :translation, :rotation, :scale, :matrix, :skin, keyword_init: true)
  Skin = Struct.new(:joints, :inverse_bind_matrices, :skeleton, keyword_init: true)

  class Channel
    attr_reader :node_index, :path, :times, :values, :interpolation

    def initialize(node_index:, path:, times:, values:, interpolation: "LINEAR")
      @node_index, @path, @times, @values, @interpolation = node_index, path.to_sym, times, values, interpolation
    end

    def sample(time, loop: false)
      return value_at(0) if @times.empty?
      duration = @times.last
      time %= duration if loop && duration.positive?
      return value_at(0) if time <= @times.first
      return value_at(@times.length - 1) if time >= @times.last
      index = @times.each_index.find { |candidate| @times[candidate + 1] && time < @times[candidate + 1] } || @times.length - 2
      span = @times[index + 1] - @times[index]
      amount = span.zero? ? 0.0 : (time - @times[index]) / span
      return value_at(index) if @interpolation == "STEP"
      raise UnsupportedError, "unsupported interpolation: #{@interpolation}" unless %w[LINEAR CUBICSPLINE].include?(@interpolation)
      interpolate(value_at(index), value_at(index + 1), amount, index: index, span: span)
    end

    private

    def value_at(index)
      @interpolation == "CUBICSPLINE" ? @values[index * 3 + 1] : @values[index]
    end

    def interpolate(first, second, amount, index:, span:)
      if @interpolation == "CUBICSPLINE"
        outgoing = @values[index * 3 + 2]
        incoming = @values[(index + 1) * 3]
        t2 = amount * amount
        t3 = t2 * amount
        result = first.zip(second, outgoing, incoming).map do |left, right, out, incoming_value|
          (2 * t3 - 3 * t2 + 1) * left + (t3 - 2 * t2 + amount) * out * span + (-2 * t3 + 3 * t2) * right + (t3 - t2) * incoming_value * span
        end
        return normalize_rotation(result) if @path == :rotation && result.length == 4
        return result
      end
      if @path == :rotation && first.length == 4
        return Quat.slerp(
          Quat.new(x: first[0], y: first[1], z: first[2], w: first[3]),
          Quat.new(x: second[0], y: second[1], z: second[2], w: second[3]),
          amount
        ).to_a
      end
      first.zip(second).map { |left, right| left + (right - left) * amount }
    end

    def normalize_rotation(value)
      length = Math.sqrt(value.sum { |component| component * component })
      length.zero? ? value : value.map { |component| component / length }
    end
  end

  class Animation
    attr_reader :name, :channels, :duration

    def initialize(name:, channels:)
      @name, @channels = name, channels
      @duration = channels.flat_map(&:times).max.to_f
    end

    def sample(time, loop: false)
      @channels.each_with_object({}) do |channel, pose|
        (pose[channel.node_index] ||= {})[channel.path] = channel.sample(time, loop: loop)
      end
    end
  end

  module Skinning
    module_function

    def apply(primitive, skin, scene, method: :lbs)
      raise ArgumentError, "unknown skinning method: #{method}" unless %i[lbs dqs].include?(method.to_sym)
      return primitive.positions.dup unless skin
      matrices = skin.joints.map.with_index do |joint, index|
        scene.world_matrix(joint) * (skin.inverse_bind_matrices&.[](index) || Mat4.identity)
      end
      return apply_dual_quaternions(primitive, matrices) if method.to_sym == :dqs && matrices.all? { |matrix| rigid_transform?(matrix) }
      return apply_linear_blend(primitive, matrices)
    end

    def apply_normals(primitive, skin, scene, method: :lbs)
      raise ArgumentError, "unknown skinning method: #{method}" unless %i[lbs dqs].include?(method.to_sym)
      return nil unless primitive.normals
      return primitive.normals.map(&:dup) unless skin

      matrices = skin.joints.map.with_index do |joint, index|
        scene.world_matrix(joint) * (skin.inverse_bind_matrices&.[](index) || Mat4.identity)
      end
      if method.to_sym == :dqs && matrices.all? { |matrix| rigid_transform?(matrix) }
        return apply_dual_quaternion_normals(primitive, matrices)
      end
      apply_linear_blend_normals(primitive, matrices)
    end

    def apply_linear_blend(primitive, matrices)
      primitive.positions.each_with_index.map do |position, index|
        joints = primitive.joints&.[](index) || [0]
        weights = primitive.weights&.[](index) || [1.0]
        total = weights.sum
        weights = weights.map { |weight| weight / total } if total.positive? && total != 1.0
        result = Vec3.new(x: 0.0, y: 0.0, z: 0.0)
        joints.each_with_index { |joint, weight_index| result += matrices[joint].transform(position) * (weights[weight_index] || 0) if matrices[joint] }
        result
      end
    end
    private_class_method :apply_linear_blend

    def apply_linear_blend_normals(primitive, matrices)
      primitive.normals.each_with_index.map do |normal, index|
        joints = primitive.joints&.[](index) || [0]
        weights = primitive.weights&.[](index) || [1.0]
        raise ArgumentError, "skin weights do not match joints" if joints.length != weights.length
        total = weights.sum
        weights = weights.map { |weight| weight / total } if total.positive? && total != 1.0
        result = Vec3.new(x: 0.0, y: 0.0, z: 0.0)
        joints.each_with_index do |joint, weight_index|
          matrix = matrices[joint]
          result += inverse_transpose_direction(matrix, normal) * (weights[weight_index] || 0) if matrix
        end
        result.normalize
      end
    end
    private_class_method :apply_linear_blend_normals

    def inverse_transpose_direction(matrix, direction)
      a, b, c = matrix[0, 0], matrix[0, 1], matrix[0, 2]
      d, e, f = matrix[1, 0], matrix[1, 1], matrix[1, 2]
      g, h, i = matrix[2, 0], matrix[2, 1], matrix[2, 2]
      determinant = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
      return direction_from_matrix(matrix, direction) if determinant.abs < 1e-12

      inverse = [
        (e * i - f * h) / determinant, (c * h - b * i) / determinant, (b * f - c * e) / determinant,
        (f * g - d * i) / determinant, (a * i - c * g) / determinant, (c * d - a * f) / determinant,
        (d * h - e * g) / determinant, (b * g - a * h) / determinant, (a * e - b * d) / determinant
      ]
      Vec3.new(
        x: inverse[0] * direction.x + inverse[3] * direction.y + inverse[6] * direction.z,
        y: inverse[1] * direction.x + inverse[4] * direction.y + inverse[7] * direction.z,
        z: inverse[2] * direction.x + inverse[5] * direction.y + inverse[8] * direction.z
      )
    end
    private_class_method :inverse_transpose_direction

    def direction_from_matrix(matrix, direction)
      Vec3.new(
        x: matrix[0, 0] * direction.x + matrix[0, 1] * direction.y + matrix[0, 2] * direction.z,
        y: matrix[1, 0] * direction.x + matrix[1, 1] * direction.y + matrix[1, 2] * direction.z,
        z: matrix[2, 0] * direction.x + matrix[2, 1] * direction.y + matrix[2, 2] * direction.z
      )
    end
    private_class_method :direction_from_matrix

    def rigid_transform?(matrix)
      basis = [
        [matrix[0, 0], matrix[1, 0], matrix[2, 0]],
        [matrix[0, 1], matrix[1, 1], matrix[2, 1]],
        [matrix[0, 2], matrix[1, 2], matrix[2, 2]]
      ]
      lengths = basis.map { |axis| Math.sqrt(axis.sum { |value| value * value }) }
      return false unless lengths.all? { |length| (length - 1.0).abs < 1e-5 }

      dot = ->(first, second) { first.zip(second).sum { |left, right| left * right } }
      dot.call(basis[0], basis[1]).abs < 1e-5 && dot.call(basis[0], basis[2]).abs < 1e-5 && dot.call(basis[1], basis[2]).abs < 1e-5
    end
    private_class_method :rigid_transform?

    def apply_dual_quaternions(primitive, matrices)
      dual_quaternions = matrices.map { |matrix| dual_quaternion(matrix) }
      primitive.positions.each_with_index.map do |position, index|
        real, dual = blended_dual_quaternion(primitive, index, dual_quaternions)
        transform_dual_quaternion(position, real, dual)
      end
    end
    private_class_method :apply_dual_quaternions

    def apply_dual_quaternion_normals(primitive, matrices)
      dual_quaternions = matrices.map { |matrix| dual_quaternion(matrix) }
      primitive.normals.each_index.map do |index|
        real, = blended_dual_quaternion(primitive, index, dual_quaternions)
        transform_dual_quaternion_vector(primitive.normals[index], real)
      end
    end
    private_class_method :apply_dual_quaternion_normals

    def blended_dual_quaternion(primitive, index, dual_quaternions)
      joints = primitive.joints&.[](index) || [0]
      weights = primitive.weights&.[](index) || [1.0]
      raise ArgumentError, "skin weights do not match joints" if joints.length != weights.length
      reference = nil
      real = Array.new(4, 0.0)
      dual = Array.new(4, 0.0)
      joints.each_with_index do |joint, weight_index|
        pair = dual_quaternions[joint]
        next unless pair
        weight = weights[weight_index].to_f
        reference ||= pair[0]
        sign = quaternion_dot(reference, pair[0]).negative? ? -1.0 : 1.0
        4.times do |component|
          real[component] += pair[0][component] * weight * sign
          dual[component] += pair[1][component] * weight * sign
        end
      end
      [real, dual]
    end
    private_class_method :blended_dual_quaternion

    def dual_quaternion(matrix)
      basis = [
        [matrix[0, 0], matrix[1, 0], matrix[2, 0]],
        [matrix[0, 1], matrix[1, 1], matrix[2, 1]],
        [matrix[0, 2], matrix[1, 2], matrix[2, 2]]
      ]
      lengths = basis.map { |axis| Math.sqrt(axis.sum { |value| value * value }) }
      raise UnsupportedError, "DQS requires rigid skin transforms" unless lengths.all? { |length| (length - 1.0).abs < 1e-5 }
      dot = ->(first, second) { first.zip(second).sum { |left, right| left * right } }
      raise UnsupportedError, "DQS requires orthogonal skin transforms" unless dot.call(basis[0], basis[1]).abs < 1e-5 && dot.call(basis[0], basis[2]).abs < 1e-5 && dot.call(basis[1], basis[2]).abs < 1e-5

      trace = matrix[0, 0] + matrix[1, 1] + matrix[2, 2]
      rotation = if trace.positive?
        root = Math.sqrt(trace + 1.0) * 2
        [
          (matrix[2, 1] - matrix[1, 2]) / root,
          (matrix[0, 2] - matrix[2, 0]) / root,
          (matrix[1, 0] - matrix[0, 1]) / root,
          0.25 * root
        ]
      elsif matrix[0, 0] > matrix[1, 1] && matrix[0, 0] > matrix[2, 2]
        root = Math.sqrt(1.0 + matrix[0, 0] - matrix[1, 1] - matrix[2, 2]) * 2
        [0.25 * root, (matrix[0, 1] + matrix[1, 0]) / root, (matrix[0, 2] + matrix[2, 0]) / root, (matrix[2, 1] - matrix[1, 2]) / root]
      elsif matrix[1, 1] > matrix[2, 2]
        root = Math.sqrt(1.0 + matrix[1, 1] - matrix[0, 0] - matrix[2, 2]) * 2
        [(matrix[0, 1] + matrix[1, 0]) / root, 0.25 * root, (matrix[1, 2] + matrix[2, 1]) / root, (matrix[0, 2] - matrix[2, 0]) / root]
      else
        root = Math.sqrt(1.0 + matrix[2, 2] - matrix[0, 0] - matrix[1, 1]) * 2
        [(matrix[0, 2] + matrix[2, 0]) / root, (matrix[1, 2] + matrix[2, 1]) / root, 0.25 * root, (matrix[1, 0] - matrix[0, 1]) / root]
      end
      rotation = quaternion_normalize(rotation)
      translation = [matrix[0, 3], matrix[1, 3], matrix[2, 3], 0.0]
      [rotation, quaternion_scale(quaternion_multiply(translation, rotation), 0.5)]
    end
    private_class_method :dual_quaternion

    def transform_dual_quaternion(point, real, dual)
      real = quaternion_normalize(real)
      dual = quaternion_scale(dual, 1.0 / Math.sqrt(real.sum { |value| value * value }))
      rotated = quaternion_multiply(quaternion_multiply(real, [point.x, point.y, point.z, 0.0]), quaternion_conjugate(real))
      translation = quaternion_multiply(dual, quaternion_conjugate(real)).first(3).map { |value| value * 2 }
      Vec3.new(x: rotated[0] + translation[0], y: rotated[1] + translation[1], z: rotated[2] + translation[2])
    end
    private_class_method :transform_dual_quaternion

    def transform_dual_quaternion_vector(vector, real)
      real = quaternion_normalize(real)
      rotated = quaternion_multiply(quaternion_multiply(real, [vector.x, vector.y, vector.z, 0.0]), quaternion_conjugate(real))
      Vec3.new(x: rotated[0], y: rotated[1], z: rotated[2]).normalize
    end
    private_class_method :transform_dual_quaternion_vector

    def quaternion_multiply(first, second)
      ax, ay, az, aw = first
      bx, by, bz, bw = second
      [aw * bx + ax * bw + ay * bz - az * by, aw * by - ax * bz + ay * bw + az * bx, aw * bz + ax * by - ay * bx + az * bw, aw * bw - ax * bx - ay * by - az * bz]
    end
    private_class_method :quaternion_multiply

    def quaternion_conjugate(quaternion)
      [-quaternion[0], -quaternion[1], -quaternion[2], quaternion[3]]
    end
    private_class_method :quaternion_conjugate

    def quaternion_scale(quaternion, scale)
      quaternion.map { |value| value * scale }
    end
    private_class_method :quaternion_scale

    def quaternion_normalize(quaternion)
      length = Math.sqrt(quaternion.sum { |value| value * value })
      length.zero? ? [0.0, 0.0, 0.0, 1.0] : quaternion_scale(quaternion, 1.0 / length)
    end
    private_class_method :quaternion_normalize

    def quaternion_dot(first, second)
      first.zip(second).sum { |left, right| left * right }
    end
    private_class_method :quaternion_dot
  end

  class Scene
    attr_reader :meshes, :nodes, :materials, :animations, :skins

    def initialize(meshes: [], nodes: [], materials: [], animations: [], skins: [])
      @meshes = meshes
      @nodes = nodes
      @materials = materials
      @animations = animations
      @skins = skins
    end

    def world_matrix(node)
      node = @nodes[node] if node.is_a?(Integer)
      index = @nodes.index(node)
      raise ArgumentError, "node is not part of the scene" unless index
      parent = @nodes.find { |candidate| candidate.children.to_a.include?(index) }
      local = node.matrix || Mat4.trs(node.translation, node.rotation, node.scale)
      parent ? world_matrix(parent) * local : local
    end

    def apply_pose!(pose)
      pose.each do |index, values|
        node = @nodes[index]
        raise ArgumentError, "invalid node index: #{index}" unless node
        values.each do |key, value|
          node[key] = case key.to_sym
          when :translation, :scale then Vec3.new(x: value[0], y: value[1], z: value[2])
          when :rotation then Quat.new(x: value[0], y: value[1], z: value[2], w: value[3]).normalize
          else raise ArgumentError, "unsupported animation path: #{key}"
          end
        end
      end
      self
    end
  end

  module OBJ
    module_function

    def load(path, normals: :keep, triangulate: true, base_dir: File.dirname(path))
      lines = File.read(path).gsub(/\\\r?\n/, "").lines
      positions = []
      uvs = []
      normal_values = []
      groups = Hash.new { |hash, key| hash[key] = { vertices: {}, positions: [], uvs: [], normals: [], indices: [] } }
      material_name = "default"
      materials = {}
      lines.each do |line|
        line = line.strip
        next if line.empty? || line.start_with?("#")
        fields = line.split
        case fields.shift
        when "v" then positions << Vec3.new(x: fields[0].to_f, y: fields[1].to_f, z: fields[2].to_f)
        when "vt" then uvs << Vec2.new(x: fields[0].to_f, y: fields[1].to_f)
        when "vn" then normal_values << Vec3.new(x: fields[0].to_f, y: fields[1].to_f, z: fields[2].to_f)
        when "usemtl" then material_name = fields.join(" ")
        when "mtllib"
          file = File.expand_path(fields.join(" "), base_dir)
          materials.merge!(MTL.load(file)) if File.file?(file)
        when "f"
          raise ArgumentError, "OBJ face needs at least three vertices" if fields.length < 3
          face = fields.map { |token| parse_vertex(token, positions.length, uvs.length, normal_values.length) }
          triangles = if triangulate && face.length > 3
            (1...face.length - 1).map { |index| [face[0], face[index], face[index + 1]] }
          else
            [face]
          end
          triangles.each do |triangle|
            triangle.each do |key|
              group = groups[material_name]
              index = group[:vertices][key]
              unless index
                index = group[:vertices].length
                group[:vertices][key] = index
                group[:positions] << positions[key[0]]
                group[:uvs] << (key[1] && uvs[key[1]])
                group[:normals] << (key[2] && normal_values[key[2]])
              end
              group[:indices] << index
            end
          end
        end
      end
      primitives = groups.map do |name, group|
        primitive = Primitive.new(positions: group[:positions], uvs: group[:uvs].compact.empty? ? nil : group[:uvs], normals: group[:normals].compact.empty? ? nil : group[:normals], indices: group[:indices], material: materials[name] || Material.new(name: name, base_color_factor: [1, 1, 1, 1]))
        primitive.normals = generate_normals(primitive) if normals == :flat || (normals == :smooth && primitive.normals.nil?) || normals == :force_smooth
        primitive
      end
      Scene.new(meshes: [Mesh.new(name: File.basename(path), primitives: primitives)], materials: materials.values)
    end

    def parse_vertex(token, position_count, uv_count, normal_count)
      values = token.split("/", -1)
      raise ArgumentError, "invalid OBJ vertex: #{token}" unless values.length.between?(1, 3)
      values.map!.with_index do |text, index|
        next nil if text.nil? || text.empty?
        raise ArgumentError, "invalid OBJ vertex: #{token}" unless text.match?(/\A-?\d+\z/)
        value = text.to_i
        count = [position_count, uv_count, normal_count][index]
        resolved = value.negative? ? count + value : value - 1
        raise ArgumentError, "OBJ index out of range: #{token}" unless resolved.between?(0, count - 1)
        resolved
      end
      raise ArgumentError, "OBJ position index is missing" if values[0].nil?
      [values[0], values[1], values[2]]
    end
    private_class_method :parse_vertex

    def generate_normals(primitive)
      normals = Array.new(primitive.positions.length) { Vec3.new(x: 0, y: 0, z: 0) }
      primitive.indices.each_slice(3) do |a, b, c|
        normal = (primitive.positions[b] - primitive.positions[a]).cross(primitive.positions[c] - primitive.positions[a])
        [a, b, c].each { |index| normals[index] = normals[index] + normal }
      end
      normals.map(&:normalize)
    end
    private_class_method :generate_normals
  end

  module MTL
    module_function

    def load(path)
      current = nil
      result = {}
      File.read(path).each_line do |line|
        fields = line.split
        next if fields.empty? || fields.first.start_with?("#")
        case fields.shift
        when "newmtl"
          current = Material.new(name: fields.join(" "), base_color_factor: [1, 1, 1, 1])
          result[current.name] = current
        when "Kd" then current.base_color_factor = fields.map(&:to_f) + [1]
        when "d" then current.base_color_factor[3] = fields.first.to_f
        when "map_Kd" then current.base_color_texture = TextureRef.new(path: File.expand_path(fields.join(" "), File.dirname(path)))
        end
      end
      result
    end
  end

  module GLTF
    module_function

    COMPONENTS = { "SCALAR" => 1, "VEC2" => 2, "VEC3" => 3, "VEC4" => 4, "MAT2" => 4, "MAT3" => 9, "MAT4" => 16 }.freeze
    FORMATS = { 5120 => "c", 5121 => "C", 5122 => "s<", 5123 => "S<", 5125 => "L<", 5126 => "e" }.freeze

    def load(path, load_images: true, base_dir: File.dirname(path))
      json, binary = document(path)
      raise UnsupportedError, "glTF 2.x is required" unless json.dig("asset", "version").to_s.match?(/\A2\./)
      raise UnsupportedError, "required glTF extensions are not supported" unless json.fetch("extensionsRequired", []).empty?
      buffers = json.fetch("buffers", []).map { |buffer| buffer_data(buffer, binary, base_dir) }
      views = json.fetch("bufferViews", [])
      access = lambda do |index|
        definition = json.fetch("accessors")[index]
        view = definition["bufferView"] && views[definition["bufferView"]]
        count = definition["count"]
        components = COMPONENTS.fetch(definition["type"])
        format = FORMATS.fetch(definition["componentType"])
        item_size = format_size(format) * components
        read_values = lambda do |buffer_view, byte_offset, value_count, value_format, value_size, value_components|
          raw = buffers.fetch(buffer_view.fetch("buffer"))
          view_start = buffer_view.fetch("byteOffset", 0)
          start = view_start + byte_offset
          view_end = view_start + buffer_view.fetch("byteLength")
          stride = buffer_view["byteStride"] || value_size
          raise ArgumentError, "invalid glTF accessor stride" if stride < value_size
          needed = value_count.zero? ? 0 : (value_count - 1) * stride + value_size
          raise ArgumentError, "glTF accessor exceeds buffer view" if start + needed > view_end || start + needed > raw.bytesize
          Array.new(value_count) { |item| raw.byteslice(start + item * stride, value_size).unpack(value_format * value_components) }
        end
        values = if view
          read_values.call(view, definition.fetch("byteOffset", 0), count, format, item_size, components)
        else
          raise ArgumentError, "glTF accessor count is missing" unless count
          Array.new(count) { Array.new(components, 0) }
        end
        values.map! { |value| normalize(value, definition["componentType"]) } if definition["normalized"]
        sparse = definition["sparse"]
        if sparse
          sparse_count = sparse.fetch("count")
          raise ArgumentError, "sparse accessor count exceeds accessor count" if sparse_count > count
          index_view = views.fetch(sparse.fetch("indices").fetch("bufferView"))
          index_component = sparse.fetch("indices").fetch("componentType")
          index_format = { 5121 => "C", 5123 => "S<", 5125 => "L<" }.fetch(index_component) { raise ArgumentError, "invalid sparse index component type" }
          index_values = read_values.call(index_view, sparse["indices"].fetch("byteOffset", 0), sparse_count, index_format, format_size(index_format), 1).map(&:first)
          value_view = views.fetch(sparse.fetch("values").fetch("bufferView"))
          sparse_values = read_values.call(value_view, sparse["values"].fetch("byteOffset", 0), sparse_count, format, item_size, components)
          index_values.each_with_index do |target, sparse_index|
            raise ArgumentError, "sparse accessor index is out of range" if target >= count
            value = sparse_values[sparse_index]
            value = normalize(value, definition["componentType"]) if definition["normalized"]
            values[target] = value
          end
        end
        values.map { |value| definition["type"] == "SCALAR" ? value.first : value }
      end
      image_refs = json.fetch("images", []).map do |image|
        uri = image["uri"]
        path = if uri && !uri.start_with?("data:")
          expanded = File.expand_path(uri, base_dir)
          root = File.realpath(base_dir) + File::SEPARATOR
          raise ArgumentError, "image escapes base_dir" unless expanded.start_with?(root)
          raise ArgumentError, "image escapes base_dir" unless File.realpath(expanded).start_with?(root)
          expanded
        end
        bytes = if load_images && uri&.start_with?("data:")
          raise UnsupportedError, "unsupported glTF image URI" unless uri.match?(/\Adata:[^,]*;base64,/)
          uri.split(",", 2).last.unpack1("m0")
        elsif load_images && path
          File.binread(path)
        end
        if load_images && bytes
          require "tessel"
          TextureRef.new(path: path, image: Tessel.decode(bytes))
        else
          TextureRef.new(path: path, image: nil)
        end
      end
      image_refs = json.fetch("images", []).each_with_index.map do |image, index|
        next image_refs[index] if image["uri"]
        view = views.fetch(image.fetch("bufferView"))
        raw = buffers.fetch(view.fetch("buffer")).byteslice(view.fetch("byteOffset", 0), view.fetch("byteLength"))
        image_refs[index].tap do |reference|
          if load_images
            require "tessel"
            reference.image = Tessel.decode(raw)
          end
        end
      end
      textures = json.fetch("textures", []).map { |texture| image_refs[texture["source"]] }
      materials = json.fetch("materials", []).map do |material|
        pbr = material["pbrMetallicRoughness"] || {}
        texture = pbr["baseColorTexture"] && textures[pbr["baseColorTexture"]["index"]]
        Material.new(name: material["name"], base_color_factor: pbr["baseColorFactor"] || [1, 1, 1, 1], base_color_texture: texture, emissive: material["emissiveFactor"] || [0, 0, 0], alpha_mode: material["alphaMode"] || "OPAQUE")
      end
      meshes = json.fetch("meshes", []).map do |mesh|
        primitives = mesh.fetch("primitives").map do |primitive|
          raise UnsupportedError, "only TRIANGLES glTF primitives are supported" unless (primitive["mode"] || 4) == 4
          attributes = primitive.fetch("attributes")
          position_values = access.call(attributes.fetch("POSITION"))
          colors = attributes["COLOR_0"] && access.call(attributes["COLOR_0"]).map do |value|
            value = [value] unless value.is_a?(Array)
            Color.new(r: value[0], g: value[1], b: value[2], a: value.fetch(3, 1.0))
          end
          Primitive.new(
            positions: position_values.map { |v| Vec3.new(x: v[0], y: v[1], z: v[2]) },
            normals: attributes["NORMAL"] && access.call(attributes["NORMAL"]).map { |v| Vec3.new(x: v[0], y: v[1], z: v[2]) },
            uvs: attributes["TEXCOORD_0"] && access.call(attributes["TEXCOORD_0"]).map { |v| Vec2.new(x: v[0], y: v[1]) },
            colors: colors,
            joints: attributes["JOINTS_0"] && access.call(attributes["JOINTS_0"]),
            weights: attributes["WEIGHTS_0"] && access.call(attributes["WEIGHTS_0"]),
            indices: primitive["indices"] ? access.call(primitive["indices"]) : (0...position_values.length).to_a,
            material: materials[primitive["material"] || 0]
          )
        end
        Mesh.new(name: mesh["name"], primitives: primitives)
      end
      nodes = json.fetch("nodes", []).map do |node|
        translation = node["translation"] || [0, 0, 0]
        rotation = node["rotation"] || [0, 0, 0, 1]
        scale = node["scale"] || [1, 1, 1]
        matrix = node["matrix"]&.each_slice(4)&.to_a
        Node.new(name: node["name"], children: node["children"] || [], mesh: node["mesh"] && meshes[node["mesh"]], translation: Vec3.new(x: translation[0], y: translation[1], z: translation[2]), rotation: Quat.new(x: rotation[0], y: rotation[1], z: rotation[2], w: rotation[3]), scale: Vec3.new(x: scale[0], y: scale[1], z: scale[2]), matrix: matrix && Mat4.new(matrix.transpose.flatten), skin: node["skin"])
      end
      skins = json.fetch("skins", []).map do |skin|
        inverse_bind_matrices = if skin["inverseBindMatrices"]
          access.call(skin["inverseBindMatrices"]).map { |value| Mat4.new(value.each_slice(4).to_a.transpose.flatten) }
        end
        Skin.new(joints: skin.fetch("joints"), inverse_bind_matrices: inverse_bind_matrices, skeleton: skin["skeleton"])
      end
      animations = json.fetch("animations", []).map do |animation|
        samplers = animation.fetch("samplers")
        channels = animation.fetch("channels").map do |channel|
          sampler = samplers.fetch(channel.fetch("sampler"))
          target = channel.fetch("target")
          Channel.new(node_index: target.fetch("node"), path: target.fetch("path"), times: access.call(sampler.fetch("input")), values: access.call(sampler.fetch("output")), interpolation: sampler.fetch("interpolation", "LINEAR"))
        end
        Animation.new(name: animation["name"], channels: channels)
      end
      Scene.new(meshes: meshes, nodes: nodes, materials: materials, animations: animations, skins: skins)
    end

    def document(path)
      bytes = File.binread(path)
      return [JSON.parse(bytes), nil] unless bytes.start_with?("glTF")
      raise ArgumentError, "invalid GLB" unless bytes.bytesize >= 12 && bytes.byteslice(4, 8).unpack("L<2") == [2, bytes.bytesize]
      cursor = 12
      json = nil
      binary = nil
      while cursor < bytes.bytesize
        raise ArgumentError, "truncated GLB chunk" if cursor + 8 > bytes.bytesize
        length, type = bytes.byteslice(cursor, 8).unpack("L<2")
        raise ArgumentError, "truncated GLB chunk" if cursor + 8 + length > bytes.bytesize
        chunk = bytes.byteslice(cursor + 8, length)
        if type == 0x4E4F534A
          json = JSON.parse(chunk)
        elsif type == 0x004E4942
          binary = chunk
        end
        cursor += 8 + length
      end
      raise ArgumentError, "GLB is missing JSON" unless json
      [json, binary]
    end
    private_class_method :document

    def buffer_data(definition, binary, base_dir)
      uri = definition["uri"]
      data = if uri.nil?
        binary || (raise ArgumentError, "glTF buffer has no data")
      elsif uri.start_with?("data:")
        raise UnsupportedError, "unsupported glTF data URI" unless uri.match?(/\Adata:[^,]*;base64,/)
        uri.split(",", 2).last.unpack1("m0")
      else
        path = File.expand_path(uri, base_dir)
        raise ArgumentError, "buffer escapes base_dir" unless path.start_with?(File.expand_path(base_dir) + File::SEPARATOR)
        raise ArgumentError, "buffer escapes base_dir" unless File.realpath(path).start_with?(File.realpath(base_dir) + File::SEPARATOR)
        File.binread(path)
      end
      raise ArgumentError, "glTF buffer is truncated" if data.bytesize < definition.fetch("byteLength")
      data
    end
    private_class_method :buffer_data

    def format_size(format)
      { "c" => 1, "C" => 1, "s<" => 2, "S<" => 2, "L<" => 4, "e" => 4 }.fetch(format)
    end
    private_class_method :format_size

    def normalize(values, component)
      values.map do |value|
        case component
        when 5120 then [value / 127.0, -1.0].max
        when 5122 then [value / 32_767.0, -1.0].max
        when 5121 then value / 255.0
        when 5123 then value / 65_535.0
        when 5125 then value / 4_294_967_295.0
        else value
        end
      end
    end
    private_class_method :normalize
  end

  module_function

  def load(path, **options)
    extension = File.extname(path).downcase
    extension == ".obj" ? OBJ.load(path, **options) : GLTF.load(path, **options)
  end
end
