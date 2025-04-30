module Data
  abstract class Base
    # The database file
    property db : String

    # Initialize the database connection
    def initialize(@db : String)
    end

    def with_db(create = false, &block : DB::Database -> T) : T forall T
      if !create && !File.exists?(@db)
        puts "ERR: Database file `#{@db}` does not exist. Use init to create it."
        exit -404 # file not found :o)
      end

      # Open the database connection and yield it to the block
      DB.open "sqlite3://./#{@db}" do |db|
        db.exec("PRAGMA foreign_keys = ON")
        db.exec("PRAGMA application_id = 0x2fefd315")
        db.exec("PRAGMA journal_mode = WAL")

        yield db

        # Set the analysis limit and optimize the database
        # After close.
        db.exec("PRAGMA analysis_limit=400")
        db.exec("PRAGMA optimize")
      end
    end

  end
end
