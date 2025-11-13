require "./list"

module Command
  module Dataset
    class List < Base
      description "List the datasets"

      def run_impl
        root.with_db do |db|
          datasets = db.query_all("SELECT name FROM datasets", &.read(String))

          if datasets.empty?
            puts "No datasets found."
          else
            puts "Datasets:"
            datasets.each do |dataset|
              puts "- #{dataset}"
            end
          end
        end
      end
    end
  end
end
