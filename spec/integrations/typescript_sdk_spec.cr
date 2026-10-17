require "../spec_helper"
require "../../src/integrations/typescript_sdk"

describe CrystalCog::Integrations do
  describe CrystalCog::Integrations::TypeScriptSDKConfig do
    it "creates config with default values" do
      config = CrystalCog::Integrations::TypeScriptSDKConfig.new
      config.host.should eq "0.0.0.0"
      config.port.should eq 8080
      config.cors_origins.should eq ["*"]
      config.enable_websocket.should be_true
      config.api_prefix.should eq "/api/v1"
      config.auth_enabled.should be_false
    end

    it "creates config with custom values" do
      config = CrystalCog::Integrations::TypeScriptSDKConfig.new(
        host: "127.0.0.1",
        port: 3000,
        auth_enabled: true,
        api_key: "secret-key"
      )

      config.host.should eq "127.0.0.1"
      config.port.should eq 3000
      config.auth_enabled.should be_true
      config.api_key.should eq "secret-key"
    end
  end

  describe CrystalCog::Integrations::APIResponse do
    it "creates success response" do
      response = CrystalCog::Integrations::APIResponse.new(
        success: true,
        data: JSON.parse({"key" => "value"}.to_json)
      )

      response.success.should be_true
      response.error.should be_nil
      response.request_id.should_not be_empty
    end

    it "creates error response" do
      response = CrystalCog::Integrations::APIResponse.new(
        success: false,
        error: "Something went wrong"
      )

      response.success.should be_false
      response.error.should eq "Something went wrong"
    end

    it "serializes to JSON" do
      response = CrystalCog::Integrations::APIResponse.new(
        success: true,
        data: JSON.parse({"atoms" => [1, 2, 3]}.to_json)
      )

      json = response.to_json
      json.should contain "\"success\":true"
      json.should contain "\"requestId\""
      json.should contain "\"timestamp\""
    end
  end

  describe CrystalCog::Integrations::TruthValueDTO do
    it "creates with default values" do
      tv = CrystalCog::Integrations::TruthValueDTO.new
      tv.strength.should eq 1.0
      tv.confidence.should eq 1.0
    end

    it "creates with custom values" do
      tv = CrystalCog::Integrations::TruthValueDTO.new(strength: 0.8, confidence: 0.9)
      tv.strength.should eq 0.8
      tv.confidence.should eq 0.9
    end
  end

  describe CrystalCog::Integrations::AttentionValueDTO do
    it "creates with default values" do
      av = CrystalCog::Integrations::AttentionValueDTO.new
      av.sti.should eq 0.0
      av.lti.should eq 0.0
    end

    it "creates with custom values" do
      av = CrystalCog::Integrations::AttentionValueDTO.new(sti: 100.0, lti: 50.0)
      av.sti.should eq 100.0
      av.lti.should eq 50.0
    end
  end

  describe CrystalCog::Integrations::AtomDTO do
    it "creates with default values" do
      atom = CrystalCog::Integrations::AtomDTO.new
      atom.id.should eq ""
      atom.type.should eq "ConceptNode"
    end

    it "creates with custom values" do
      atom = CrystalCog::Integrations::AtomDTO.new(
        id: "atom-1",
        type: "PredicateNode",
        name: "likes",
        truth_value: CrystalCog::Integrations::TruthValueDTO.new(strength: 0.9)
      )

      atom.id.should eq "atom-1"
      atom.type.should eq "PredicateNode"
      atom.name.should eq "likes"
      atom.truth_value.not_nil!.strength.should eq 0.9
    end

    it "serializes and deserializes" do
      original = CrystalCog::Integrations::AtomDTO.new(
        id: "test-id",
        type: "ConceptNode",
        name: "Dog"
      )

      json = original.to_json
      restored = CrystalCog::Integrations::AtomDTO.from_json(json)

      restored.id.should eq original.id
      restored.type.should eq original.type
      restored.name.should eq original.name
    end
  end

  describe CrystalCog::Integrations::QueryDTO do
    it "creates query" do
      query = CrystalCog::Integrations::QueryDTO.new(
        pattern: "Dog",
        limit: 50,
        offset: 10
      )

      query.pattern.should eq "Dog"
      query.limit.should eq 50
      query.offset.should eq 10
    end

    it "serializes and deserializes" do
      original = CrystalCog::Integrations::QueryDTO.new(pattern: "test")
      json = original.to_json
      restored = CrystalCog::Integrations::QueryDTO.from_json(json)

      restored.pattern.should eq "test"
    end
  end

  describe CrystalCog::Integrations::WSMessage do
    it "creates message" do
      msg = CrystalCog::Integrations::WSMessage.new(
        type: CrystalCog::Integrations::WSMessageType::Subscribe,
        channel: "atoms"
      )

      msg.type.should eq CrystalCog::Integrations::WSMessageType::Subscribe
      msg.channel.should eq "atoms"
      msg.id.should_not be_empty
    end

    it "serializes to JSON" do
      msg = CrystalCog::Integrations::WSMessage.new(
        type: CrystalCog::Integrations::WSMessageType::Query,
        payload: JSON.parse({"pattern" => "test"}.to_json)
      )

      json = msg.to_json
      json.should contain "\"type\":\"query\""
    end

    it "parses from JSON" do
      json = {
        "type"    => "subscribe",
        "channel" => "atoms",
        "id"      => "test-id",
      }.to_json

      msg = CrystalCog::Integrations::WSMessage.from_json(json)
      msg.should_not be_nil
      msg.not_nil!.type.should eq CrystalCog::Integrations::WSMessageType::Subscribe
      msg.not_nil!.channel.should eq "atoms"
    end

    it "handles invalid JSON" do
      msg = CrystalCog::Integrations::WSMessage.from_json("invalid")
      msg.should be_nil
    end
  end

  describe CrystalCog::Integrations::SDKAtomSpace do
    atomspace = CrystalCog::Integrations::SDKAtomSpace.new

    it "starts empty" do
      space = CrystalCog::Integrations::SDKAtomSpace.new
      space.stats["atom_count"].should eq 0
    end

    it "adds atoms" do
      space = CrystalCog::Integrations::SDKAtomSpace.new
      atom = CrystalCog::Integrations::AtomDTO.new(
        type: "ConceptNode",
        name: "Dog"
      )

      result = space.add_atom(atom)
      result.id.should_not be_empty
      result.name.should eq "Dog"
      space.stats["atom_count"].should eq 1
    end

    it "gets atom by ID" do
      space = CrystalCog::Integrations::SDKAtomSpace.new
      atom = space.add_atom(CrystalCog::Integrations::AtomDTO.new(name: "Cat"))

      retrieved = space.get_atom(atom.id)
      retrieved.should_not be_nil
      retrieved.not_nil!.name.should eq "Cat"
    end

    it "returns nil for missing atom" do
      space = CrystalCog::Integrations::SDKAtomSpace.new
      space.get_atom("nonexistent").should be_nil
    end

    it "gets atoms by type" do
      space = CrystalCog::Integrations::SDKAtomSpace.new
      space.add_atom(CrystalCog::Integrations::AtomDTO.new(type: "ConceptNode", name: "A"))
      space.add_atom(CrystalCog::Integrations::AtomDTO.new(type: "ConceptNode", name: "B"))
      space.add_atom(CrystalCog::Integrations::AtomDTO.new(type: "PredicateNode", name: "C"))

      concepts = space.get_atoms("ConceptNode")
      concepts.size.should eq 2
    end

    it "updates atoms" do
      space = CrystalCog::Integrations::SDKAtomSpace.new
      atom = space.add_atom(CrystalCog::Integrations::AtomDTO.new(name: "Original"))

      updated = space.update_atom(atom.id, CrystalCog::Integrations::AtomDTO.new(name: "Updated"))
      updated.should_not be_nil
      updated.not_nil!.name.should eq "Updated"
    end

    it "deletes atoms" do
      space = CrystalCog::Integrations::SDKAtomSpace.new
      atom = space.add_atom(CrystalCog::Integrations::AtomDTO.new(name: "ToDelete"))

      space.delete_atom(atom.id).should be_true
      space.get_atom(atom.id).should be_nil
    end

    it "queries atoms" do
      space = CrystalCog::Integrations::SDKAtomSpace.new
      space.add_atom(CrystalCog::Integrations::AtomDTO.new(name: "Dog"))
      space.add_atom(CrystalCog::Integrations::AtomDTO.new(name: "Cat"))
      space.add_atom(CrystalCog::Integrations::AtomDTO.new(name: "Dogfish"))

      results = space.query("Dog")
      results.size.should eq 2
    end

    it "supports pagination" do
      space = CrystalCog::Integrations::SDKAtomSpace.new
      10.times { |i| space.add_atom(CrystalCog::Integrations::AtomDTO.new(name: "Atom#{i}")) }

      page1 = space.get_atoms(limit: 3, offset: 0)
      page1.size.should eq 3

      page2 = space.get_atoms(limit: 3, offset: 3)
      page2.size.should eq 3
    end
  end

  describe CrystalCog::Integrations::TypeScriptGenerator do
    generator = CrystalCog::Integrations::TypeScriptGenerator.new

    it "generates type definitions" do
      types = generator.generate_types
      types.should contain "export interface Atom"
      types.should contain "export interface TruthValue"
      types.should contain "export interface AttentionValue"
      types.should contain "export interface QueryInput"
      types.should contain "export class CrystalCogClient"
    end

    it "generates client code" do
      client = generator.generate_client_code
      client.should contain "class CrystalCogClient"
      client.should contain "async getAtoms"
      client.should contain "async createAtom"
      client.should contain "connect(): Promise<void>"
      client.should contain "subscribe"
    end

    it "generates package.json" do
      package = generator.generate_package_json
      json = JSON.parse(package)

      json["name"].should eq JSON::Any.new("@crystalcog/sdk")
      json["version"].should eq JSON::Any.new("0.1.0")
      json["main"].should eq JSON::Any.new("dist/index.js")
    end
  end
end
