# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec) { |task| task.ruby_opts = ["-I../rbgl/lib", "-I../larb/lib"] }

task default: :spec
task verify: :spec
