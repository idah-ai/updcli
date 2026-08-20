module Command
  module Entry
    class Show < Base
      Log = ::Log.for("entry.show")

      description "Show an entry"
      option "id", "i", "id", required: true, type: :string

      def run_impl
        entries = root.database.query_all(
          "SELECT id, media_url, metadata FROM entries WHERE id = ?",
          option("id")
        ) do |entry|
          {
            id:        entry.read(String),
            media_url: entry.read(String),
            metadata:  entry.read(String).try { |str| JSON.parse(str) }
          }
        end

        if entries.empty?
          Log.warn { "No entries found." }
        else
          entries.each do |entry|
            Log.info { entry.to_json }
          end
        end
      end
    end
  end
end
