require "spec"
require "../../src/opencog/opencog"

private def catalog_application_query : String
  File.read(File.expand_path("../../examples/integration_examples/query_catalog.oql", __DIR__))
end

private def catalog_application_space : AtomSpace::AtomSpace
  space = AtomSpace::AtomSpace.new
  product_type = space.add_concept_node("Product")
  approved_price = space.add_concept_node("ApprovedPrice")
  price_predicate = space.add_predicate_node("price")
  {"Apple" => "3.5", "Free sample" => "0", "Kale" => nil, "Pear" => "-5", "Plum" => "6", "Stone" => "8"}.each do |name, amount|
    product = space.add_concept_node(name)
    space.add_inheritance_link(product, product_type) unless name == "Stone"
    next unless amount
    price = space.add_node(AtomSpace::AtomType::NUMBER_NODE, amount)
    space.add_evaluation_link(price_predicate, space.add_list_link([product, price]))
    space.add_inheritance_link(price, approved_price) unless name == "Plum"
  end
  space
end

private def catalog_application_rows(space : AtomSpace::AtomSpace)
  OpenCog::Query.create_query_interface(space).query(catalog_application_query)
end

describe "Catalog application through OpenCog::Query" do
  it "returns ordered, projected bindings and preserves approved price atoms including zero" do
    space = catalog_application_space
    rows = catalog_application_rows(space)
    rows.map { |row| row.bindings["product"].name }.should eq(["Apple", "Free sample", "Kale", "Pear", "Plum"])
    rows.first.bindings.keys.sort.should eq(["display_price", "price", "product"])
    rows.first.bindings["product"].should be(space.get_nodes_by_name("Apple").first)
    rows.first.bindings["price"].should be(space.get_nodes_by_name("3.5").first)
    rows.first.bindings["display_price"].should be(rows.first.bindings["price"])
    rows[1].bindings["display_price"].should be(rows[1].bindings["price"])
    rows[1].bindings["price"].name.should eq("0")
    rows[1].bindings["price"].type.should eq(AtomSpace::AtomType::NUMBER_NODE)
  end

  it "keeps absent, filter-rejected and incomplete optional prices unbound with a display fallback" do
    space = catalog_application_space
    by_product = catalog_application_rows(space).to_h { |row| {row.bindings["product"].name, row} }
    {"Kale", "Pear", "Plum"}.each do |name|
      row = by_product[name]
      row.bindings.has_key?("price").should be_false
      row.bindings.keys.sort.should eq(["display_price", "product"])
      row.bindings["display_price"].name.should eq("Contact us")
      row.bindings["display_price"].type.should eq(AtomSpace::AtomType::CONCEPT_NODE)
    end
    # An otherwise valid price must not turn a non-product into a catalog row.
    by_product.has_key?("Stone").should be_false
    space.get_nodes_by_name("-5").size.should eq(1)
    space.get_nodes_by_name("6").size.should eq(1)
  end

  it "returns no products from an empty graph instead of manufacturing a fallback row" do
    catalog_application_rows(AtomSpace::AtomSpace.new).should be_empty
  end

  it "returns the same real bindings through the module-level application entry point" do
    space = catalog_application_space
    direct = catalog_application_rows(space)
    delegated = OpenCog::Query.execute_query(space, catalog_application_query)
    delegated.size.should eq(direct.size)
    delegated.zip(direct).each do |actual, expected|
      actual.bindings.keys.sort.should eq(expected.bindings.keys.sort)
      actual.confidence.should eq(expected.confidence)
      actual.bindings.each do |name, atom|
        {atom.type, atom.name}.should eq({expected.bindings[name].type, expected.bindings[name].name})
        atom.should be(expected.bindings[name]) unless name == "display_price" && !actual.bindings.has_key?("price")
      end
    end
  end

  it "reports malformed fallback expressions as parse errors at the public boundary" do
    space = catalog_application_space
    malformed = catalog_application_query.sub("COALESCE($price, \"Contact us\")", "COALESCE()")
    interface = OpenCog::Query.create_query_interface(space)
    expect_raises(OpenCog::QueryLanguage::QueryParseException, "COALESCE needs at least one value") do
      interface.query(malformed)
    end
    expect_raises(OpenCog::QueryLanguage::QueryParseException, "COALESCE needs at least one value") do
      OpenCog::Query.execute_query(space, malformed)
    end
  end

  it "does not persist display fallbacks or change stored atom identities and truth values" do
    space = catalog_application_space
    before = space.get_all_atoms
    truth_values = before.map { |atom| {atom.truth_value, atom.truth_value.strength, atom.truth_value.confidence} }
    catalog_application_rows(space)
    space.size.should eq(before.size)
    before.each_with_index do |atom, i|
      space.get_atom(atom.handle).should be(atom)
      atom.truth_value.should be(truth_values[i][0])
      {atom.truth_value.strength, atom.truth_value.confidence}.should eq({truth_values[i][1], truth_values[i][2]})
    end
    space.get_nodes_by_name("Contact us").should be_empty
    space.get_atoms_by_type(AtomSpace::AtomType::VARIABLE_NODE).should be_empty
  end
end
