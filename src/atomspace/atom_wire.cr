# Content-addressed JSON form of atoms, for moving them between AtomSpaces
# whose handles differ (CogServer HTTP API, CogStorageNode, cluster sync).
#
#   {"type": "CONCEPT_NODE", "name": "cat", "truth_value": {"strength": 0.9, "confidence": 0.8}}
#   {"type": "INHERITANCE_LINK", "outgoing": [{"type": "CONCEPT_NODE", "name": "cat"}, ...]}
#
# A link's outgoing atoms are nested, so an atom is fully described by its
# JSON and never by a handle that only means something to its sender.

require "json"
require "digest/sha256"
require "./atom"
require "./truthvalue"

module AtomSpace
  module AtomWire
    def self.write(json : JSON::Builder, atom : Atom) : Nil
      json.object do
        json.field "type", atom.type.to_s
        if atom.is_a?(Node)
          json.field "name", atom.name
        else
          json.field "outgoing" do
            json.array { atom.outgoing.each { |child| write(json, child) } }
          end
        end
        json.field "truth_value" do
          json.object do
            json.field "strength", atom.truth_value.strength
            json.field "confidence", atom.truth_value.confidence
          end
        end
      end
    end

    # A content address: the same atom has the same address in every
    # process, whatever its handle. A link's address is a hash over its
    # type and its children's addresses (a Merkle hash of the hypergraph).
    def self.address(atom : Atom) : String
      content = if atom.is_a?(Node)
                  "N:#{atom.type}:#{atom.name.bytesize}:#{atom.name}"
                else
                  "L:#{atom.type}:#{atom.outgoing.map { |child| address(child) }.join(',')}"
                end
      Digest::SHA256.hexdigest(content)[0, 32]
    end

    # A position on a 64-bit hash ring that every process computes alike
    # (`String#hash` is seeded per process and cannot be used for this).
    def self.ring_position(key : String) : UInt64
      IO::ByteFormat::BigEndian.decode(UInt64, Digest::SHA256.digest(key)[0, 8])
    end

    def self.to_json(atom : Atom) : String
      JSON.build { |json| write(json, atom) }
    end

    # Build the atom described by `data`, detached from any AtomSpace. An
    # outgoing entry may also be an integer handle; `resolve` turns it into
    # the receiver's atom (an unknown handle raises).
    def self.read(data : JSON::Any, &resolve : Handle -> Atom?) : Atom
      type = AtomType.parse(data["type"].as_s)
      tv = truth_value(data["truth_value"]?)
      if type.node?
        Node.new(type, data["name"].as_s, tv)
      elsif type.link?
        outgoing = data["outgoing"].as_a.map do |child|
          if number = child.as_i64?
            handle = number.to_u64
            resolve.call(handle) || raise ArgumentError.new("Unknown outgoing handle: #{handle}")
          else
            read(child, &resolve)
          end
        end
        Link.new(type, outgoing, tv)
      else
        raise ArgumentError.new("Expected a concrete node or link type")
      end
    end

    def self.read(data : JSON::Any) : Atom
      read(data) { |_handle| nil.as(Atom?) }
    end

    def self.truth_value(data : JSON::Any?) : TruthValue
      return TruthValue::DEFAULT_TV unless data && data.as_h?
      SimpleTruthValue.new(number(data["strength"]), number(data["confidence"]))
    end

    private def self.number(value : JSON::Any) : Float64
      value.as_f? || value.as_i64.to_f
    end

    # Add a detached atom and everything below it to `atomspace`, returning
    # the AtomSpace's own instance. With `replace`, the given truth values
    # overwrite existing ones instead of being merged with them.
    def self.intern(atom : Atom, atomspace : AtomSpace, replace : Bool = false) : Atom
      return atom if atomspace.get_atom(atom.handle).same?(atom)
      tv = atom.truth_value
      added = if atom.is_a?(Node)
                atomspace.add_node(atom.type, atom.name, tv)
              else
                children = atom.outgoing.map { |child| intern(child, atomspace, replace) }
                atomspace.add_link(atom.type, children, tv)
              end
      # Adding merges with what was there; a store asks for exactly `tv`.
      added.truth_value = tv if replace && added.truth_value != tv
      added
    end
  end
end
