# frozen_string_literal: true

require "rbgl"

module Riggle
  module RBGL
    module_function

    def to_rbgl(primitive, layout: :auto, warnings: true)
      engine = ::RBGL::Engine
      layout = build_layout(primitive) if layout == :auto
      layout = { position_only: engine::VertexLayout.method(:position_only), position_color: engine::VertexLayout.method(:position_color), position_normal_uv: engine::VertexLayout.method(:position_normal_uv), position_normal_uv_color: engine::VertexLayout.method(:position_normal_uv_color) }.fetch(layout).call if layout.is_a?(Symbol)
      raise ArgumentError, "layout must be an RBGL vertex layout" unless layout.is_a?(engine::VertexLayout)

      missing = layout.attributes.keys.filter { |name| %i[normal uv color].include?(name) && primitive.public_send(attribute_source(name)).nil? }
      warn "Riggle::RBGL: filling missing attributes: #{missing.join(', ')}" if warnings && missing.any?
      vertices = primitive.positions.each_index.map do |index|
        layout.attributes.keys.to_h { |name| [name, attribute_value(primitive, name, index)] }
      end
      [engine::VertexBuffer.from_array(layout, vertices), engine::IndexBuffer.new(primitive.indices || (0...primitive.positions.length).to_a)]
    end

    def build_layout(primitive)
      engine = ::RBGL::Engine
      engine::VertexLayout.new do
        attribute :position, 3
        attribute :normal, 3 if primitive.normals
        attribute :uv, 2 if primitive.uvs
        attribute :color, 4 if primitive.colors
      end
    end

    def attribute_source(name)
      { normal: :normals, uv: :uvs, color: :colors }.fetch(name)
    end
    private_class_method :attribute_source

    def attribute_value(primitive, name, index)
      case name
      when :position then primitive.positions.fetch(index).to_a
      when :normal then primitive.normals&.[](index)&.to_a || [0.0, 0.0, 1.0]
      when :uv then primitive.uvs&.[](index)&.to_a || [0.0, 0.0]
      when :color then primitive.colors&.[](index)&.to_a || [1.0, 1.0, 1.0, 1.0]
      else raise ArgumentError, "unsupported RBGL vertex attribute: #{name}"
      end
    end
    private_class_method :attribute_value
  end
end
