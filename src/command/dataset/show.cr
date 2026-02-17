module Command
  module Dataset
    class Show < Base
      Log = ::Log.for("dataset.show")

      description "Show a dataset"

      option "id", "i", "id", required: true, type: :string

      def run_impl
        datasets = root.database.query_all(
          "SELECT id, name, modality FROM datasets WHERE id = ?",
          option("id")
        ) do |dataset|
          {
            id:       dataset.read(String),
            name:     dataset.read(String),
            modality: dataset.read(String),
          }
        end
        if datasets.empty?
          Log.warn { "No datasets found." }
        else
          datasets.each do |dataset|
            Log.info { dataset.to_json }
          end
        end
      end
    end
  end
end
