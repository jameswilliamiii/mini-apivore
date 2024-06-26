# frozen_string_literal: true

require "mini_apivore/version"
require "hashie"

module MiniApivore
  class Swagger < Hash
    include Hashie::Extensions::MergeInitializer

    NONVERB_PATH_ITEMS = "parameters"

    def validate
      filepath = File.expand_path("../../data/swagger_#{version}_schema.json", __dir__)
      if File.exist?(filepath)
        schema = File.read(filepath)
      else
        raise "Unknown/unsupported Swagger version to validate against: #{version}"
      end
      JSON::Validator.fully_validate(schema, self)
    end

    def version
      self["openapi"] || self["swagger"]
    end

    def base_path
      self["basePath"] || ""
    end

    def each_response(&block)
      self["paths"].each do |path, path_data|
        next if vendor_specific_tag?(path)

        path_data.each do |verb, method_data|
          next if NONVERB_PATH_ITEMS.include?(verb)
          next if vendor_specific_tag?(verb)

          if method_data["responses"].nil?
            raise "No responses found in swagger for path '#{path}', " \
              "verb #{verb}: #{method_data.inspect}"
          end
          method_data["responses"].each do |response_code, response_data|
            schema_location = nil
            response_data.extend(Hashie::Extensions::DeepFind)
            if response_data.deep_find("$ref")
              keys = response_data.deep_find("$ref").split("/")
              schema_location = Fragment.new(keys)
            elsif response_data.deep_find("schema")
              keys = ["#", "paths", path, verb, "responses", response_code]
              keys += find_schema_path(response_data)
              schema_location = Fragment.new(keys)
            end
            block.call(path, verb, response_code, schema_location)
          end
        end
      end
    end

    def find_schema_path(hash, path = [])
      hash.each do |key, value|
        current_path = path + [key]
        return current_path if key == "schema"

        if value.is_a?(Hash)
          schema_path = find_schema_path(value, current_path)
          return schema_path if schema_path
        end
      end
      nil
    end

    def vendor_specific_tag?(tag)
      tag =~ /\Ax-.*/
    end
  end
end
