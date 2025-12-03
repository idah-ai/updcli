module Command
  class Init < Base
    Log = ::Log.for("init")
    Schema = {{ read_file("sql/schema.sql") }}

    description "Initialize a new UPD file."

    def run_impl
      Schema.split(";").each do |stmt|
        stmt = stmt.strip

        next if stmt.empty?

        root.database.exec stmt
      rescue e
        raise Command::Error.new("Failed to execute statement: #{stmt}\nError: #{e.message}", self)
      end

      Log.info{ "Generated empty UPD successfully." }
    end

  end
end
