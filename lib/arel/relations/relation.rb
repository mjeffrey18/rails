module Arel
  class Relation
    def session
      Session.new
    end
    
    def to_sql(formatter = Sql::SelectStatement.new(self))
      formatter.select [
        "SELECT     #{attributes.collect { |a| a.to_sql(Sql::SelectClause.new(self)) }.join(', ')}",
        "FROM       #{table_sql(Sql::TableReference.new(self))}",
        (joins(self)                                                                                    unless joins(self).blank? ),
        ("WHERE     #{selects.collect { |s| s.to_sql(Sql::WhereClause.new(self)) }.join("\n\tAND ")}"   unless selects.blank?     ),
        ("ORDER BY  #{orders.collect { |o| o.to_sql(Sql::OrderClause.new(self)) }.join(', ')}"          unless orders.blank?      ),
        ("GROUP BY  #{groupings.collect { |g| g.to_sql(Sql::GroupClause.new(self)) }.join(', ')}"       unless groupings.blank?   ),
        ("LIMIT     #{taken}"                                                                           unless taken.blank?       ),
        ("OFFSET    #{skipped}"                                                                         unless skipped.blank?     )
      ].compact.join("\n"), name
    end
    alias_method :to_s, :to_sql
    
    def inclusion_predicate_sql
      "IN"
    end
    
    def call(connection = engine.connection)
      results = connection.execute(to_sql)
      rows = []
      results.each do |row|
        rows << attributes.zip(row).to_hash
      end
      rows
    end
    
    def bind(relation)
      self
    end
    
    def christener
      @christener ||= Sql::Christener.new
    end
    
    def aggregation?
      false
    end
    
    module Enumerable
      include ::Enumerable

      def each(&block)
        session.read(self).each(&block)
      end

      def first
        session.read(self).first
      end
    end
    include Enumerable

    module Operable
      def join(other = nil, join_type = "INNER JOIN")
        case other
        when String
          Join.new(other, self)
        when Relation
          JoinOperation.new(join_type, self, other)
        else
          self
        end
      end

      def outer_join(other = nil)
        join(other, "LEFT OUTER JOIN")
      end
      
      def select(*predicates)
        predicates.all?(&:blank?) ? self : Selection.new(self, *predicates)
      end

      def project(*attributes)
        attributes.all?(&:blank?) ? self : Projection.new(self, *attributes)
      end
      
      def alias
        Alias.new(self)
      end

      def order(*attributes)
        attributes.all?(&:blank?) ? self : Order.new(self, *attributes)
      end
      
      def take(taken = nil)
        taken.blank?? self : Take.new(self, taken)
      end
      
      def skip(skipped = nil)
        skipped.blank?? self : Skip.new(self, skipped)
      end
  
      def group(*groupings)
        groupings.all?(&:blank?) ? self : Grouping.new(self, *groupings)
      end
      
      module Writable
        def insert(record)
          session.create Insertion.new(self, record); self
        end

        def update(assignments)
          session.update Update.new(self, assignments); self
        end

        def delete
          session.delete Deletion.new(self); self
        end
      end
      include Writable
  
      JoinOperation = Struct.new(:join_sql, :relation1, :relation2) do
        def on(*predicates)
          Join.new(join_sql, relation1, relation2, *predicates)
        end
      end
    end
    include Operable
    
    module AttributeAccessable
      def [](index)
        case index
        when Symbol, String
          find_attribute_matching_name(index)
        when Attribute, Expression
          find_attribute_matching_attribute(index)
        when Array
          index.collect { |i| self[i] }
        end
      end
      
      def find_attribute_matching_name(name)
        attributes.detect { |a| a.alias_or_name.to_s == name.to_s }
      end
      
      # TESTME - added relation_for(x)[x] because of AR
      def find_attribute_matching_attribute(attribute)
        attributes.select { |a| a.match?(attribute) }.max do |a1, a2|
          # FIXME relation_for(a1)[a1] should be a1.original or something
          (attribute / relation_for(a1)[a1]) <=> (attribute / relation_for(a2)[a2])
        end
      end
      
      def find_attribute_matching_attribute_with_memoization(attribute)
        @attribute_for_attribute ||= Hash.new do |h, a|
          h[a] = find_attribute_matching_attribute_without_memoization(a)
        end
        @attribute_for_attribute[attribute]
      end
      alias_method_chain :find_attribute_matching_attribute, :memoization
    end
    include AttributeAccessable

    module DefaultOperations
      def attributes;             []  end
      def selects;                []  end
      def orders;                 []  end
      def inserts;                []  end
      def groupings;              []  end
      def joins(formatter = nil); nil end
      def taken;                  nil end
      def skipped;                nil end
    end
    include DefaultOperations
  end
end