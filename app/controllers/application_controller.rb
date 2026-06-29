class ApplicationController < ActionController::API
  include Pagy::Backend

  rescue_from ActiveRecord::RecordNotFound,      with: :not_found
  rescue_from ActiveRecord::RecordInvalid,       with: :unprocessable
  rescue_from ActionController::ParameterMissing, with: :bad_request

  private

  def not_found(e)
    render json: { error: "Not found", message: e.message }, status: :not_found
  end

  def unprocessable(e)
    render json: { error: "Unprocessable", errors: e.record.errors.full_messages }, status: :unprocessable_content
  end

  def bad_request(e)
    render json: { error: "Bad request", message: e.message }, status: :bad_request
  end

  def paginate_meta(pagy)
    {
      current_page: pagy.page,
      total_pages: pagy.pages,
      total_count: pagy.count,
      per_page: pagy.limit
    }
  end
end
