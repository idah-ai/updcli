module Command
  module Metadata
    class Show < Base
      Log = ::Log.for("metadata:show")
      description "Show Metadata"

      def run_impl
        metadatas = root.database.query_all(
          "SELECT key, value FROM metadata"
        ) do |metadata|
          [
            metadata.read(String),
            metadata.read(String)
          ]
        end
        if metadatas.empty?
          Log.info { "No metadatas found." }
        else
          Log.info { metadatas.to_h.to_json }
        end
      end
    end
  end
end
