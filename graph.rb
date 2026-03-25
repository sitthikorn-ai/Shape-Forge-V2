module VBO::ShapeForge

  class Graph
    attr_accessor :vertices, :start_vertices

    def initialize(input)
      @vertices = {}
      @transformation = Geom::Transformation.new
      @start_vertices = []

      if input.is_a?(Hash)
        initialize_from_hash(input)
      elsif input.is_a?(Sketchup::Entities) || input.is_a?(Sketchup::Selection)
        initialize_from_sketchup_entities(input)
      elsif input.is_a?(Array)
        if input.first.is_a?(Array) && input.first.length == 2
          initialize_from_lines(input)
        elsif input.first.is_a?(Sketchup::Drawingelement)
          initialize_from_sketchup_entities(input)
        else
          raise ArgumentError, "Invalid input type. Expected Array of edges."
        end
      else
        raise ArgumentError, "Invalid input type. Expected Hash or Sketchup::Entities."
      end
    end

    def edges
      edges_array = []

      @vertices.each do |vertex, connected_vertices|
        connected_vertices.each do |connected_vertex|
          edge = [vertex, connected_vertex].sort_by { |v| [v.x, v.y, v.z] }
          edges_array << edge unless edges_array.include?(edge)
        end
      end

      edges_array
    end

    def transform!(transformation)
      @transformation = transformation * @transformation
      @vertices = @vertices.map{|vertex, connected_vertices|
         [
          vertex.transform(transformation),
          connected_vertices.map{|v|
            v.transform(transformation)
          }
        ]
      }.to_h
      self
    end

    def draw_to_entities(entities)
      edges.each do |edge|
        start_point, end_point = edge
        entities.add_edges(start_point, end_point)
      end
    end

    def super_graph
      grouped_edges = []

      remaining_edges = edges.dup

      while remaining_edges.any?
        current_edge = remaining_edges.shift
        current_group = [current_edge]

        direction = current_edge[0].vector_to(current_edge[1])

        while (next_edge = find_and_remove_edge_with_direction(remaining_edges, current_edge, direction))
          current_edge = next_edge
          current_group << current_edge
        end

        grouped_edges << current_group
      end

      grouped_edges
    end

    def simply_graph
      # puts "simple graph"
      # puts "start vertices: #{@start_vertices.map{|c| c.transform(@transformation)}}" if @start_vertices
      # puts "edges: #{edges}"
      edges.group_by{|c|
        line = [
          c[0],
          c[0].vector_to(c[1]).normalize
        ]

        cons_line = [ORIGIN, line[1]]

        tr = Geom::Transformation.translation(line[0].vector_to(ORIGIN))
        direction = [
            line[0].transform(tr).to_a.map{|c| c.round(3)},
            line[1].to_a.map{|c| c.round(3)}
          ]
        [
          direction,
          ORIGIN.vector_to(ORIGIN.project_to_line(line)).to_a.map{|c| c.round(3)}
        ]
      }.values.map{|c|
        e = merge_edges_to_polylines(c)
        # puts "pline: #{e}"
        e.map{|f|
          n = [f[0], f[-1]]
          n = n.reverse if !is_start?(n[0]) && is_start?(n[1])
          n
        }
      }.flatten(1)
    end

    def move_vertex(vertex, vector)
      return false unless @vertices.key?(vertex)

      # Calculate the new position of the vertex
      new_vertex = vertex + vector

      # Update the connections in the graph
      connected_vertices = @vertices.delete(vertex)
      @vertices[new_vertex] = connected_vertices

      # Update the connections of the connected vertices
      connected_vertices.each do |connected_vertex|
        @vertices[connected_vertex].delete(vertex)
        @vertices[connected_vertex].add(new_vertex)
      end

      true
    end

    def move_vertices(vertices, vector)
      visited = Set.new

      vertices.each do |vertex|
        next if visited.include?(vertex)

        move_vertex(vertex, vector)
        visited << vertex

        # Add connected vertices to the visited set
        connected_vertices = @vertices[vertex]
        connected_vertices.each do |connected_vertex|
          visited << connected_vertex
        end
      end
    end

    def remove_vertex(vertex)
      return false unless @vertices.key?(vertex)

      # Remove the connections of the vertex
      connected_vertices = @vertices.delete(vertex)

      # Update the connections of the connected vertices
      connected_vertices.each do |connected_vertex|
        @vertices[connected_vertex].delete(vertex)
      end

      true
    end

    def insert_vertex_on_edge(vertex1, vertex2, new_vertex)
      # Check if the edge exists
      if @vertices[vertex1].include?(vertex2) && @vertices[vertex2].include?(vertex1)
        # Remove the old edge
        @vertices[vertex1].delete(vertex2)
        @vertices[vertex2].delete(vertex1)

        # Add the new vertex and connect it to the existing vertices
        @vertices[new_vertex] ||= []
        @vertices[new_vertex] << vertex1
        @vertices[new_vertex] << vertex2

        # Connect the existing vertices to the new vertex
        @vertices[vertex1] << new_vertex
        @vertices[vertex2] << new_vertex
      else
        raise ArgumentError, "The edge between the given vertices doesn't exist in the graph."
      end
    end

    def point_on_edge?(point, edge, tolerance = 1e-6)
      vertex1, vertex2 = edge
      vec1 = vertex1.vector_to(point)
      vec2 = vertex1.vector_to(vertex2)
      cross_product = vec1 * vec2

      # If the cross product length is larger than tolerance, point is not on the edge
      return false if cross_product.length > tolerance

      dot_product = vec1 % vec2
      ratio = dot_product / vec2.length2

      # If the ratio is outside of [0, 1], point is not on the edge
      return false if ratio < 0 || ratio > 1

      # Calculate the distance between point and projected point
      distance = point.distance(vertex1.linear_combination(ratio, vertex1, 1 - ratio, vertex2))

      distance <= tolerance
    end

    def contains_vertex?(point, tolerance = 1e-6)
      vertices.each do |vertex|
        return true if point.distance(vertex) <= tolerance
      end

      edges.each do |edge|
        return true if point_on_edge?(point, edge, tolerance)
      end

      false
    end

    def to_h
      graph_hash = {}

      @vertices.each do |vertex, connected_vertices|
        vertex_key = vertex.to_a.join(',')
        graph_hash[vertex_key] = connected_vertices.map { |v| v.to_a.join(',') }
      end

      graph_hash
    end

    def to_json
      self.to_h.to_json
    end

    def group_vertices_by_vector_set
      grouped_vertices = {}
      vertices.each do |vertex|
        vector_set1 = VectorSet.new(vertex, edges)
        found = false

        grouped_vertices.each do |key_vertex, group|
          vector_set2 = VectorSet.new(key_vertex, edges)

          if vector_set1.equal?(vector_set2)
            group << vertex
            found = true
            break
          end
        end

        grouped_vertices[vertex] = [vertex] unless found
      end

      grouped_vertices
    end

    def create_graph_from_simplified_graph(simplified_graph)
      graph = Graph.new({})

      simplified_graph.each do |edge|
        vertex1, vertex2 = edge
        graph.start_vertices << vertex1
        # Add vertex1 to the graph if it doesn't exist
        unless graph.vertices.key?(vertex1)
          graph.vertices[vertex1] = []
        end

        # Add vertex2 to the graph if it doesn't exist
        unless graph.vertices.key?(vertex2)
          graph.vertices[vertex2] = []
        end

        # Add the connection between vertex1 and vertex2
        graph.vertices[vertex1] << vertex2
        graph.vertices[vertex2] << vertex1
      end
      graph.start_vertices.uniq!
      graph
    end

    def is_start?(v)
      # puts "is start? #{[v]}"
      # puts "start vertices: #{@start_vertices.map{|c| c.transform(@transformation)}}"
      @start_vertices && @start_vertices.map{|c| c.transform(@transformation).to_a.map{|c| c.round(3)}}.include?(v.to_a.map{|c| c.round(3)})
    end

    def merge_edges_to_polylines(edges)
			polylines = edges.find_all{|c|
				c.length > 2
			}
			edges = edges - polylines
			vertices = Hash.new(0)
			edges.each{|edge|
				vertices[edge[0].to_a] += 1
				vertices[edge[1].to_a] += 1
			}
      # puts "merge edges to polylines"
      # puts "start vertices: #{@start_vertices.map{|c| c.transform(@transformation)}}" if @start_vertices

			while vertices.length > 0
				st = vertices.keys.find{|k| vertices[k] == 1 && is_start?(k)}
        st = vertices.keys.find{|k| vertices[k] == 1 } if st.nil?
				if st.nil?
					st = vertices.keys.find{|k| vertices[k] == 2}
				end
				if st
					polylines << [st]
					# edge = edges.find_all{|e| e.include?(st)}.min_by{|e|
          #   v1 = e[0].vector_to(e[1])
          #   other_vertex = e.find{|v| v != st}
          #   v2 = st.vector_to(other_vertex)
          #   v1.angle_between(v2).radians.round % 180
          # }
          edge = edges.find{|e| e.include?(st)}
					while edge
						po = edge.find{|v| v != st}
						polylines[-1] << po.to_a if polylines[-1][-1].to_a != po.to_a
						vertices[st] -= 1
						vertices[po] -= 1
						vertices.delete(st) if vertices[st] < 1
						vertices.delete(po) if vertices[po] < 1
						edges.delete_if{|e| e.include?(st) && e.include?(po)}
						st = po
						edge = edges.find{|e| e.include?(st)}
					end
					vertices.delete(st)
				else
					break
				end
			end
			polylines.delete_if{|x| x.length < 2 || x.any?{|y| y.empty? || !y}}
      if polylines.any?
			  polylines.map{|x| x.map{|y| Geom::Point3d.new(y)}}
      else
        edges
      end
		end

    private

    def initialize_from_hash(input_hash)
      input_hash.each do |key, value|
        vertex = Geom::Point3d.new(key)
        @vertices[vertex] = value.map { |v| Geom::Point3d.new(v) }
      end
    end

    def initialize_from_sketchup_entities(entities)
      # Entities can be invalid (deleted) during undo/redo. Accessing them raises TypeError.
      begin
        edges = entities.grep(Sketchup::Edge)
      rescue TypeError
        # reference to deleted Entities – initialize as empty graph and return safely
        @start_vertices = []
        return
      end
      @start_vertices = edges.map{|e| e.start.position}.uniq
      edges.each do |edge|

        start_vertex = edge.start.position
        end_vertex = edge.end.position

        @vertices[start_vertex] ||= []
        @vertices[start_vertex] << end_vertex

        @vertices[end_vertex] ||= []
        @vertices[end_vertex] << start_vertex
      end
    end

    def initialize_from_lines(lines)
      @start_vertices = lines.map{|e| e[0]}.uniq
      lines.each do |edge|
        start_vertex = edge[0]
        end_vertex = edge[1]

        @vertices[start_vertex] ||= []
        @vertices[start_vertex] << end_vertex

        @vertices[end_vertex] ||= []
        @vertices[end_vertex] << start_vertex
      end
    end

    def find_and_remove_edge_with_direction(edges, current_edge, direction)
      edges.each_with_index do |edge, index|
        vec =  edge[0].vector_to(edge[1])
        angle = vec.angle_between(direction).radians % 180
        if (edge[0] == current_edge[1] && angle < 0.1) ||
          (edge[1] == current_edge[1] && angle < 0.1)
          edges.delete_at(index)
        end
      end

      nil
    end
  end
  class VectorSet
    attr_reader :vectors

    def initialize(vertex, edges)
      neighbors = edges.select { |edge| edge.include?(vertex) }.map { |edge| edge.reject { |point| point == vertex }.first }
      @vectors = neighbors.map { |neighbor| (neighbor - vertex).normalize }
    end

    def rotation_transform(v1, v2)
      axis = v1 * v2
      return nil if axis.length.zero?
      angle = Math.acos(v1.dot(v2) / (v1.length * v2.length))
      Geom::Transformation.rotation(ORIGIN, axis, angle)
    end

    def equal?(other)
      return false if vectors.size != other.vectors.size

      sorted_vectors = vectors.sort_by { |v| [v.x, v.y, v.z] }
      other_sorted_vectors = other.vectors.sort_by { |v| [v.x, v.y, v.z] }

      sorted_vectors.each_with_index do |v1, i|
        transform = rotation_transform(v1, other_sorted_vectors[i])
        return false if transform.nil?

        transformed_vectors = sorted_vectors.map { |v| v.transform(transform) }
        return false unless transformed_vectors.zip(other_sorted_vectors).all? { |tv1, v2| tv1.samedirection?(v2) }
      end

      true
    end
  end

end
