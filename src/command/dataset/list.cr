module Command
  module Dataset
    class List < Base
      Log = ::Log.for("dataset:list")

      description "List the datasets"

      def run_impl
        datasets = root.database.query_all("SELECT id, name, modality, metadata FROM datasets") do |dataset|
          {
            id:       dataset.read(String),
            name:     dataset.read(String),
            modality: dataset.read(String),
            metadata: dataset.read(String),
          }
        end
        if datasets.empty?
          Log.info { "No datasets found." }
        else
          datasets.each do |dataset|
            Log.info { dataset.to_json }
          end
        end
      end
    end
  end
end
