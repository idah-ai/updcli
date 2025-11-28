module Command
  module Dataset
    class Show < Base
      description "Show a dataset"

      option "id", "i", "id", required: true, type: :string
      def run_impl
        root.with_db do |db|
          datasets = db.query_all(
            "SELECT id, name, modality FROM datasets WHERE id = ?",
            option("id")
          ) do |dataset|
            {
              id: dataset.read(String),
              name: dataset.read(String),
              modality: dataset.read(String)
            }
          end
          if datasets.empty?
            puts "No datasets found."
          else
            datasets.each do |dataset|
              puts dataset.to_json
            end
          end
        end
      end
    end
  end
end
