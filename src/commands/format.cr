require "json"
require "yaml"

module Format
  extend self

  def format(format : String, value) : String
    case format
    when "json"
      json(value)
    when "yaml"
      yaml(value)
    when "plain"
      plain(value)
    else
      raise ArgumentError.new("Unsupported format: #{format}")
    end
  end

  def json(data) : String
    data.to_json
  end

  def yaml(data) : String
    YAML.dump(data)
  end

  def plain(data) : String
    if data.is_a?(Array)
      data.join("\n")
    elsif data.is_a?(Hash)
      data.map { |k, v| "#{k}: #{v}" }.join("\n")
    else
      data.to_s
    end
  end
end