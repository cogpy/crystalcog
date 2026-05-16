# Navigation for CrystalCog Robotics
#
# This module implements path planning and navigation algorithms,
# enabling agents to find optimal paths in their environment while
# avoiding obstacles.

require "../cogutil/cogutil"
require "./spatial_reasoning"

module Robotics
  module Navigation
    VERSION = "0.1.0"

    class NavigationException < Exception
    end

    # Represents a waypoint in a path
    struct Waypoint
      getter position : SpatialReasoning::Position
      getter label : String

      def initialize(@position : SpatialReasoning::Position, @label : String = "")
      end
    end

    # A planned path through space
    class Path
      getter waypoints : Array(Waypoint)
      getter total_distance : Float64

      def initialize(@waypoints : Array(Waypoint) = [] of Waypoint)
        @total_distance = compute_total_distance
      end

      def empty? : Bool
        @waypoints.empty?
      end

      def length : Int32
        @waypoints.size
      end

      def add_waypoint(wp : Waypoint)
        @waypoints << wp
        @total_distance = compute_total_distance
      end

      private def compute_total_distance : Float64
        return 0.0 if @waypoints.size < 2
        total = 0.0
        (@waypoints.size - 1).times do |i|
          total += @waypoints[i].position.distance_to(@waypoints[i + 1].position)
        end
        total
      end
    end

    # Grid-based map for navigation
    class OccupancyGrid
      getter width : Int32
      getter height : Int32
      getter resolution : Float64 # meters per cell

      @grid : Array(Array(Bool))

      def initialize(@width : Int32, @height : Int32, @resolution : Float64 = 0.1)
        @grid = Array.new(@height) { Array.new(@width, false) }
      end

      def set_obstacle(x : Int32, y : Int32)
        return unless valid?(x, y)
        @grid[y][x] = true
      end

      def clear_obstacle(x : Int32, y : Int32)
        return unless valid?(x, y)
        @grid[y][x] = false
      end

      def obstacle?(x : Int32, y : Int32) : Bool
        return true unless valid?(x, y)
        @grid[y][x]
      end

      def valid?(x : Int32, y : Int32) : Bool
        x >= 0 && x < @width && y >= 0 && y < @height
      end

      # Convert world position to grid coordinates
      def world_to_grid(pos : SpatialReasoning::Position) : Tuple(Int32, Int32)
        gx = (pos.x / @resolution).to_i
        gy = (pos.y / @resolution).to_i
        {gx, gy}
      end

      # Convert grid coordinates to world position
      def grid_to_world(gx : Int32, gy : Int32) : SpatialReasoning::Position
        SpatialReasoning::Position.new(gx * @resolution, gy * @resolution)
      end
    end

    # A* path planning algorithm
    class AStarPlanner
      def initialize(@grid : OccupancyGrid)
      end

      # Plan a path from start to goal
      def plan(start : SpatialReasoning::Position, goal : SpatialReasoning::Position) : Path?
        sx, sy = @grid.world_to_grid(start)
        gx, gy = @grid.world_to_grid(goal)

        return nil if @grid.obstacle?(sx, sy) || @grid.obstacle?(gx, gy)
        return Path.new([Waypoint.new(start, "start"), Waypoint.new(goal, "goal")]) if sx == gx && sy == gy

        # A* state: {x, y} -> {g_cost, f_cost, parent}
        g_cost = Hash(Tuple(Int32, Int32), Float64).new(Float64::INFINITY)
        f_cost = Hash(Tuple(Int32, Int32), Float64).new(Float64::INFINITY)
        parent = {} of Tuple(Int32, Int32) => Tuple(Int32, Int32)

        open_set = [{sx, sy}]
        g_cost[{sx, sy}] = 0.0
        f_cost[{sx, sy}] = heuristic(sx, sy, gx, gy)

        until open_set.empty?
          # Get node with lowest f_cost
          current = open_set.min_by { |n| f_cost[n]? || Float64::INFINITY }
          open_set.delete(current)

          cx, cy = current

          if cx == gx && cy == gy
            return reconstruct_path(parent, current, start, goal)
          end

          neighbors(cx, cy).each do |nx, ny|
            next if @grid.obstacle?(nx, ny)

            move_cost = (nx != cx && ny != cy) ? Math.sqrt(2.0) : 1.0
            tentative_g = (g_cost[{cx, cy}]? || Float64::INFINITY) + move_cost

            if tentative_g < (g_cost[{nx, ny}]? || Float64::INFINITY)
              parent[{nx, ny}] = {cx, cy}
              g_cost[{nx, ny}] = tentative_g
              f_cost[{nx, ny}] = tentative_g + heuristic(nx, ny, gx, gy)
              open_set << {nx, ny} unless open_set.includes?({nx, ny})
            end
          end
        end

        nil # No path found
      end

      private def heuristic(x1 : Int32, y1 : Int32, x2 : Int32, y2 : Int32) : Float64
        # Euclidean heuristic
        Math.sqrt((x2 - x1) ** 2 + (y2 - y1) ** 2)
      end

      private def neighbors(x : Int32, y : Int32) : Array(Tuple(Int32, Int32))
        dirs = [
          {-1, -1}, {0, -1}, {1, -1},
          {-1, 0}, {1, 0},
          {-1, 1}, {0, 1}, {1, 1},
        ]
        dirs.map { |dx, dy| {x + dx, y + dy} }
          .select { |nx, ny| @grid.valid?(nx, ny) }
      end

      private def reconstruct_path(
        parent : Hash(Tuple(Int32, Int32), Tuple(Int32, Int32)),
        goal_node : Tuple(Int32, Int32),
        start_pos : SpatialReasoning::Position,
        goal_pos : SpatialReasoning::Position,
      ) : Path
        nodes = [] of Tuple(Int32, Int32)
        current = goal_node
        while parent.has_key?(current)
          nodes.unshift(current)
          current = parent[current]
        end
        nodes.unshift(current)

        waypoints = nodes.map_with_index do |node, i|
          world_pos = @grid.grid_to_world(node[0], node[1])
          label = i == 0 ? "start" : (i == nodes.size - 1 ? "goal" : "wp_#{i}")
          Waypoint.new(world_pos, label)
        end

        Path.new(waypoints)
      end
    end

    # Navigator that uses path planning and executes movement
    class Navigator
      getter current_pose : SpatialReasoning::Pose
      getter current_path : Path?

      def initialize(initial_pose : SpatialReasoning::Pose)
        @current_pose = initial_pose
        @current_path = nil
        @waypoint_index = 0
        CogUtil::Logger.info("Navigator initialized at #{initial_pose}")
      end

      def navigate_to(goal : SpatialReasoning::Position, grid : OccupancyGrid) : Bool
        planner = AStarPlanner.new(grid)
        path = planner.plan(@current_pose.position, goal)

        if path
          @current_path = path
          @waypoint_index = 0
          CogUtil::Logger.info("Path planned: #{path.length} waypoints, #{path.total_distance.round(2)}m")
          true
        else
          CogUtil::Logger.warn("No path found to #{goal}")
          false
        end
      end

      # Move towards next waypoint; returns true when destination reached
      def step(step_size : Float64 = 0.1) : Bool
        path = @current_path
        return true unless path
        return true if @waypoint_index >= path.length

        target = path.waypoints[@waypoint_index].position
        current = @current_pose.position
        dist = current.distance_to(target)

        if dist <= step_size
          @current_pose = SpatialReasoning::Pose.new(target)
          @waypoint_index += 1
          @waypoint_index >= path.length
        else
          direction = (target - current).normalize
          new_pos = current + direction * step_size
          # Compute yaw to face movement direction
          yaw = Math.atan2(direction.y, direction.x)
          @current_pose = SpatialReasoning::Pose.new(new_pos, SpatialReasoning::Orientation.new(0.0, 0.0, yaw))
          false
        end
      end

      def reached_goal? : Bool
        path = @current_path
        return true unless path
        @waypoint_index >= path.length
      end
    end
  end
end
