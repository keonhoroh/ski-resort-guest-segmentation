module Api
  class SegmentsController < ApplicationController
    # Runs before show, update, and destroy, so each of them has @segment ready.
    before_action :find_segment, only: %i[show update destroy]

    # If ClickHouse fails anywhere in this controller, reply with a safe message.
    rescue_from ClickhouseClient::Error, with: :clickhouse_failed
    rescue_from ActiveRecord::RecordNotFound, with: :not_found

    # GET /api/segments
    def index
      render json: Segment.order(updated_at: :desc).map { |segment| segment_json(segment) }
    end

    # GET /api/segments/:id
    def show
      render json: segment_json(@segment)
    end

    # POST /api/segments   Body: { "name": "...", "rules": { ... } }
    def create
      save_with_count(Segment.new(segment_params), status: :created)
    end

    # PATCH /api/segments/:id   Body: any of "name" and "rules"
    def update
      @segment.assign_attributes(segment_params)
      save_with_count(@segment, status: :ok)
    end

    # DELETE /api/segments/:id
    def destroy
      @segment.destroy!
      head :no_content
    end

    # POST /api/segments/preview   Body: { "rules": { ... } }
    # Counts matching guests for rules that have not been saved.
    def preview
      rules = request.request_parameters["rules"]
      validator = SegmentRules::Validator.new(rules)
      return render json: { errors: validator.errors }, status: :unprocessable_content unless validator.valid?

      render json: SegmentRules::Counter.call(rules)
    end

    # GET /api/segments/options
    # The allow-lists, so the web page's dropdowns always match what the server accepts.
    def options
      render json: {
        matches: SegmentRules::MATCHES.keys,
        attributes: SegmentRules::ATTRIBUTES.transform_values { |spec| spec[:values] },
        attribute_operators: SegmentRules::ATTRIBUTE_OPERATORS,
        event_types: SegmentRules::EVENT_TYPES,
        difficulties: SegmentRules::DIFFICULTIES,
        count_operators: SegmentRules::COUNT_OPERATORS.keys,
        last_event_operators: SegmentRules::LAST_EVENT_OPERATORS,
        max_rules: SegmentRules::MAX_RULES
      }
    end

    private

    def find_segment
      @segment = Segment.find(params[:id])
    end

    # Only these two keys can be set from a request. Anything else (id,
    # last_count, timestamps) is ignored.
    def segment_params
      request.request_parameters.slice("name", "rules")
    end

    # Checks the segment, counts its audience, then saves it with that count.
    def save_with_count(segment, status:)
      unless segment.valid?
        return render json: { errors: segment.errors.full_messages }, status: :unprocessable_content
      end

      segment.last_count = SegmentRules::Counter.call(segment.rules)[:count]
      segment.save!
      render json: segment_json(segment), status: status
    end

    def segment_json(segment)
      segment.as_json(only: %i[id name rules last_count created_at updated_at])
    end

    def clickhouse_failed(error)
      Rails.logger.error("Segment query failed: #{error.message}")
      render json: { error: "The segment query failed" }, status: :service_unavailable
    end

    def not_found
      render json: { error: "Segment not found" }, status: :not_found
    end
  end
end
