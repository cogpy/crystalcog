# Run from the repository root:
#   crystal run examples/integration_examples/query_catalog.cr
# A catalog application consuming real QueryResult bindings, not a new OQL feature.
require "json"
require "../../src/opencog/opencog"

# Keep stdout machine-readable. Query failures are not swallowed.
CogUtil::Logger.set_level(CogUtil::LogLevel::ERROR)
space = AtomSpace::AtomSpace.new
product_type = space.add_concept_node("Product")
approved_price = space.add_concept_node("ApprovedPrice")
price_predicate = space.add_predicate_node("price")

# Nil means no price fact. Plum has a price but no approval; Pear's approved
# price is negative and fails the OPTIONAL-local filter. Free sample costs zero.
{"Apple" => "3.5", "Free sample" => "0", "Kale" => nil, "Pear" => "-5", "Plum" => "6"}.each do |name, amount|
  product = space.add_concept_node(name)
  space.add_inheritance_link(product, product_type)
  next unless amount
  price = space.add_node(AtomSpace::AtomType::NUMBER_NODE, amount)
  space.add_evaluation_link(price_predicate, space.add_list_link([product, price]))
  space.add_inheritance_link(price, approved_price) unless name == "Plum"
end

query = File.read(File.join(__DIR__, "query_catalog.oql"))
interface = OpenCog::Query.create_query_interface(space)
rows = interface.query(query).map do |result|
  bindings = result.bindings
  {
    "product"       => bindings["product"].name,
    "price"         => bindings["price"]?.try(&.name.to_f64),
    "display_price" => bindings["display_price"].name,
  }
end
puts rows.to_json
