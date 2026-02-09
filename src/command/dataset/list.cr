module Command
  module Dataset
    class List < Base
      description "List the datasets"

      def run_impl
        datasets = root.database.query_all("SELECT id, name, modality, metadata FROM datasets") do |dataset|
          h = {
            id: dataset.read(String),
            name: dataset.read(String),
            modality: dataset.read(String),
            metadata: dataset.read(String)
          }
          # puts(h)
          # {
          #   id: h[:id],
          #   name: h[:name],
          #   modality: h[:modality],
          #   metadata: JSON.parse(h[:metadata])
          # }
        end
        if datasets.empty?
          puts "No datasets found."
        else
          datasets.each do |dataset|
            # puts JSON.parse(dataset[:metadata])
            puts dataset.to_json
          end
        end
      end
    end
  end
end
