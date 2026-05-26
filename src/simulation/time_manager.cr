# Time Management for Simulation
#
# Provides simulation time tracking and management,
# supporting variable timesteps, pause/resume, and time scaling.

module Simulation
  # Time manager for simulation
  class TimeManager
    property current_time : Float64 = 0.0
    property time_scale : Float64 = 1.0
    property paused : Bool = false
    property fixed_timestep : Float64 = 0.02  # 50 Hz default
    property max_delta_time : Float64 = 0.1   # Clamp large deltas

    getter total_steps : Int64 = 0_i64
    getter real_start_time : Time?

    @accumulated_time : Float64 = 0.0

    def initialize
      @real_start_time = nil
    end

    # Start the time manager
    def start
      @real_start_time = Time.utc
      @current_time = 0.0
      @total_steps = 0_i64
      CogUtil::Logger.debug("TimeManager started")
    end

    # Reset time to zero
    def reset
      @current_time = 0.0
      @total_steps = 0_i64
      @accumulated_time = 0.0
      @real_start_time = Time.utc
    end

    # Advance time by a delta
    def advance(dt : Float64)
      return if @paused

      # Apply time scale
      scaled_dt = dt * @time_scale

      # Clamp to max delta time
      scaled_dt = Math.min(scaled_dt, @max_delta_time)

      @current_time += scaled_dt
      @total_steps += 1
    end

    # Pause simulation time
    def pause
      @paused = true
      CogUtil::Logger.debug("TimeManager paused at t=#{@current_time}")
    end

    # Resume simulation time
    def resume
      @paused = false
      CogUtil::Logger.debug("TimeManager resumed at t=#{@current_time}")
    end

    # Toggle pause state
    def toggle_pause
      if @paused
        resume
      else
        pause
      end
    end

    # Get real elapsed time since start
    def real_elapsed_time : Time::Span?
      if start = @real_start_time
        Time.utc - start
      else
        nil
      end
    end

    # Get the ratio of simulation time to real time
    def time_ratio : Float64
      if real_elapsed = real_elapsed_time
        real_seconds = real_elapsed.total_seconds
        return 1.0 if real_seconds < 0.001
        @current_time / real_seconds
      else
        1.0
      end
    end

    # Set time scale (1.0 = real time, 2.0 = 2x speed, 0.5 = half speed)
    def set_time_scale(scale : Float64)
      @time_scale = scale.clamp(0.0, 100.0)
      CogUtil::Logger.debug("TimeManager scale set to #{@time_scale}")
    end

    # Step function for fixed timestep integration
    # Returns number of fixed steps to take
    def fixed_update(real_dt : Float64) : Int32
      return 0 if @paused

      @accumulated_time += real_dt * @time_scale
      @accumulated_time = Math.min(@accumulated_time, @max_delta_time)

      steps = (@accumulated_time / @fixed_timestep).to_i
      @accumulated_time -= steps * @fixed_timestep
      steps
    end

    # Convert simulation time to formatted string
    def format_time : String
      hours = (@current_time / 3600).to_i
      minutes = ((@current_time % 3600) / 60).to_i
      seconds = @current_time % 60

      if hours > 0
        "%02d:%02d:%05.2f" % {hours, minutes, seconds}
      else
        "%02d:%05.2f" % {minutes, seconds}
      end
    end

    # Create a timer that fires after a duration
    def create_timer(duration : Float64, &callback : -> Nil) : Timer
      Timer.new(@current_time + duration, callback)
    end
  end

  # A timer that fires at a specific simulation time
  class Timer
    getter fire_time : Float64
    getter fired : Bool = false
    @callback : Proc(Nil)

    def initialize(@fire_time : Float64, @callback : Proc(Nil))
    end

    def check(current_time : Float64) : Bool
      if !@fired && current_time >= @fire_time
        @fired = true
        @callback.call
        true
      else
        false
      end
    end

    def reset(new_fire_time : Float64)
      @fire_time = new_fire_time
      @fired = false
    end
  end

  # A scheduler for managing multiple timers
  class TimerScheduler
    @timers : Array(Timer)
    @time_manager : TimeManager

    def initialize(@time_manager : TimeManager)
      @timers = [] of Timer
    end

    def schedule(delay : Float64, &callback : -> Nil) : Timer
      timer = @time_manager.create_timer(delay, &callback)
      @timers << timer
      timer
    end

    def cancel(timer : Timer)
      @timers.delete(timer)
    end

    def update
      current = @time_manager.current_time
      @timers.each do |timer|
        timer.check(current)
      end
      # Remove fired timers
      @timers.reject!(&.fired)
    end

    def clear
      @timers.clear
    end

    def pending_count : Int32
      @timers.count { |t| !t.fired }
    end
  end

  # Frame rate limiter and statistics
  class FrameStats
    property target_fps : Float64 = 60.0
    getter actual_fps : Float64 = 0.0
    getter frame_time : Float64 = 0.0
    getter min_frame_time : Float64 = Float64::MAX
    getter max_frame_time : Float64 = 0.0

    @frame_times : Array(Float64)
    @sample_size : Int32 = 60

    def initialize(@target_fps : Float64 = 60.0)
      @frame_times = [] of Float64
    end

    def record_frame(dt : Float64)
      @frame_time = dt
      @frame_times << dt
      if @frame_times.size > @sample_size
        @frame_times.shift
      end

      @min_frame_time = Math.min(@min_frame_time, dt)
      @max_frame_time = Math.max(@max_frame_time, dt)

      # Calculate average FPS
      if @frame_times.size > 0
        avg_dt = @frame_times.sum / @frame_times.size
        @actual_fps = 1.0 / avg_dt if avg_dt > 0
      end
    end

    def reset
      @frame_times.clear
      @min_frame_time = Float64::MAX
      @max_frame_time = 0.0
      @actual_fps = 0.0
    end

    def target_frame_time : Float64
      1.0 / @target_fps
    end

    def sleep_time(current_frame_time : Float64) : Float64
      (target_frame_time - current_frame_time).clamp(0.0, target_frame_time)
    end
  end
end
