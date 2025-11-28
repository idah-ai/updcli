module Command
  module Entry
    class List < Base
      description "List the entries"

      def run_impl
        root.with_db do |db|
          entries = db.query_all("SELECT id, media_url FROM entries") do |entry|
            {
              id: entry.read(String),
              media_url: entry.read(String)
            }
          end

          if entries.empty?
            puts "No entries found."
          else
            entries.each do |entry|
              puts entry.to_json
            end
          end
        end
      end
    end
  end
end
