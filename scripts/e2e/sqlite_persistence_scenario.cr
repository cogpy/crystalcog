require "../../src/atomspace/atomspace"
require "../../src/atomspace/storage"

module NightlySQLitePersistence
  # A storage argument also permits deterministic failure fixtures without credentials.
  def self.run(storage)
    puts "AtomSpace Persistence Test"
    puts "=========================="
    begin
      raise "SQLite open failed" unless storage.open
      atomspace = AtomSpace::AtomSpace.new
      concept1 = atomspace.add_concept_node("persistent_concept_1")
      concept2 = atomspace.add_concept_node("persistent_concept_2")
      link = atomspace.add_inheritance_link(concept1, concept2)
      atoms = [concept1, concept2, link] of AtomSpace::Atom

      atoms.each do |atom|
        raise "SQLite store failed for #{atom.name} (#{atom.type})" unless storage.store_atom(atom)
      end
      puts "Stored 3 atoms to SQLite"
      raise "SQLite close failed" unless storage.close
      raise "SQLite reopen failed" unless storage.open

      # Compare content, not regenerated in-memory handles. Link equality includes
      # outgoing order/content and truth values; fetching a node alone is insufficient.
      atoms.each do |atom|
        loaded = storage.fetch_atom(atom.handle)
        raise "SQLite fetch failed for handle #{atom.handle}" unless loaded
        raise "SQLite round-trip mismatch for handle #{atom.handle}" unless loaded == atom
      end
      puts "Fetched and verified 2 concepts and 1 inheritance link after reopen"
      puts "Persistence tests passed!"
    ensure
      raise "SQLite cleanup close failed" unless storage.close
    end
  end
end
