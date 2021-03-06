class CidsController < ApplicationController
  def index
    @scope = Cid.all

    @scope = apply_filters(@scope)
    filter_counts(@scope)

    sort = params[:sort] || 'cids.wants_count'
    order = params[:order] || 'desc'

    @pagy, @cids = pagy_countless(@scope.order(sort => order))
  end

  def recent
    @range = (params[:range].presence || 7).to_i
    @scope = Want.where('created_at > ?', @range.days.ago).includes(:cid,:node)

    @pagy, @wants = pagy_countless(@scope.order('created_at DESC'))
  end

  def show
    @cid = Cid.find_by_cid!(params[:id])

    @range = (params[:range].presence || 7).to_i
    @scope = @cid.wants.includes(:node).where('created_at > ?', @range.days.ago)

    @nodes = @cid.nodes.group_by(&:id).map{|k,v| [v.first, v.length]}

    @pagy, @wants = pagy(@scope)
  end

  def wants
    redirect_to wants_nodes_path
  end

  def countries
    @scope = Node.where(pl: false).where('wants_count > 0').group_by(&:country_iso_code).sort_by{|k,v| -v.sum(&:wants_count)}
  end

  def versions
    @scope = Node.where(pl: false).where('wants_count > 0').group_by(&:minor_go_ipfs_version).sort_by{|k,v| -v.sum(&:wants_count)}
  end

  def recent_chart
    @range = (params[:range].presence || 7).to_i
    @scope = Want.where('created_at > ?', @range.days.ago).includes(:cid,:node)

    render json: @scope.group_by_day(:created_at).count
  end

  private

  def apply_filters(scope)
    scope = scope.where.not(content_length: nil) if params[:sort] == 'content_length'
    scope = scope.where.not(content_type: nil) if params[:any_content_type].present?
    scope = scope.where(content_type: params[:content_type]) if params[:content_type].present?

    return scope
  end

  def filter_counts(scope)
    @content_types = scope.unscope(where: :content_type).where.not(content_type: nil).group(:content_type).count
  end
end
