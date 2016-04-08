require_relative '../../version2'
require_relative '../../relationship'

module BELParser
  module Language
    module Version2
      module Relationships
        # HasComponent:  +A hasComponent A1+ -  For complexAbundance term A and abundance term B, +A hasComponent B+ designates B as a component of A, that complexes that are instances of A have instances of B as possible components. Note that, the stoichiometry of A is not described, nor is it stated that B is a required component. The use of hasComponent relationships is complementary to the use of functionally composed complexes and is intended to enable the assignment of components to complexes designated by names in external vocabularies. The assignment of components can potentially enable the reconciliation of equivalent complexes at knowledge assembly time.
        class HasComponent
          extend Relationship

          SHORT       = :hasComponent
          LONG        = :hasComponent
          DESCRIPTION = ' +A hasComponent A1+ -  For complexAbundance term A and abundance term B, +A hasComponent B+ designates B as a component of A, that complexes that are instances of A have instances of B as possible components. Note that, the stoichiometry of A is not described, nor is it stated that B is a required component. The use of hasComponent relationships is complementary to the use of functionally composed complexes and is intended to enable the assignment of components to complexes designated by names in external vocabularies. The assignment of components can potentially enable the reconciliation of equivalent complexes at knowledge assembly time.'.freeze

          def self.short
            SHORT
          end

          def self.long
            LONG
          end

          def self.description
            DESCRIPTION
          end
        end
      end
    end
  end
end
