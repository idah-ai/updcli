module Data
  class Init < Base
    INIT_SCHEMA = {{read_file("sql/schema.sql")}}

    def call
      with_db(create: true) do |db|
        INIT_SCHEMA.split(";").each do |stmt|
          stmt = stmt.strip
          next if stmt.empty?

          db.exec(stmt)
        end
      end
    end
  end
end

