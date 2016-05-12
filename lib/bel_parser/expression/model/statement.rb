module BELParser
  module Expression
    module Model

      # A {Statement} captures a BEL statement composed of a subject {Term},
      # +relationship+, and object {Term}. A {Statement} may be one of the
      # following common forms:
      #
      # - SUBJECT
      #   - +complex(p(HGNC:F3),p(HGNC:F7))+
      # - SUBJECT RELATIONSHIP OBJECT(Term)
      #   - +pep(complex(p(HGNC:F3),p(HGNC:F7))) => pep(p(HGNC:F9))+
      # - SUBJECT RELATIONSHIP OBJECT(Statement)
      #   - +p(HGNC:VHL) -> (p(HGNC:TNF) -> bp(GOBP:"cell death"))+
      class Statement
        attr_accessor :subject, :relationship, :object, :comment

        # Creates a {Statement} with +subject+, +relationship+, +object+, and
        # +comment+.
        #
        # @param [Term] subject
        # @param [BELParser::Language::Relationship] relationship
        # @param [Term, Statement] object
        # @param [String] comment
        def initialize(subject, relationship = nil, object = nil, comment = nil)
          raise(ArgumentError, 'subject is nil') unless subject
          @subject      = subject

          unless relationship.nil? || relationship.is_a?(BELParser::Language::Relationship)
            raise(
              ArgumentError,
              "relationship: expected nil or Relationship, actual #{@relationship.class}")
          end
          @relationship = relationship

          unless object.nil? || [Term, Statement].any?(&object.method(:is_a?))
            raise(
              ArgumentError,
              "object: expected nil, Term, or Statement, actual #{@object.class}")
          end
          @object       = object
          @comment      = comment

          if @relationship && !@object
            raise(
              ArgumentError,
              "object must be set when specifying a relationship")
          end

          if @object && !@relationship
            raise(
              ArgumentError,
              "relationsihp must be set when specifying an object")
          end
        end

        def subject_only?
          !@relationship
        end

        def simple?
          @object && @object.is_a?(Term)
        end

        def nested?
          @object && @object.is_a?(Statement)
        end

        def valid?
          # TODO Use expression validator.
        end

        def hash
          [@subject, @relationship, @object, @comment].hash
        end

        def ==(other)
          return false if other == nil
          @subject      == other.subject &&
          @relationship == other.relationship &&
          @object       == other.object &&
          @comment      == other.comment
        end
        alias :eql? :'=='

        def to_s(form = :short)
          rel =
            case form
            when :short
              @relationship && @relationship.short
            when :long
              @relationship && @relationship.long
            else
              nil
            end

          lbl =
            case
            when subject_only?
              @subject.to_s(form)
            when simple?
              "#{@subject.to_s(form)} #{rel} #{@object.to_s(form)}"
            when nested?
              "#{@subject.to_s(form)} #{rel} (#{@object.to_s(form)})"
            else
              ''
            end

          comment ? lbl + ' //' + comment : lbl
        end
      end
    end
  end
end