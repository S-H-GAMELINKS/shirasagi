class Inquiry::Agents::Nodes::FormController < ApplicationController
  include Cms::NodeFilter::View
  include SimpleCaptcha::ControllerHelpers
  include Cms::ForMemberFilter::Node

  before_action :check_release_state, only: [:new, :confirm, :create, :sent, :results], if: ->{ !@preview }
  before_action :check_reception_state, only: [:new, :confirm, :create, :sent], if: ->{ !@preview }
  before_action :check_aggregation_state, only: :results, if: ->{ !@preview }
  before_action :set_columns, only: [:new, :confirm, :create, :sent, :results]
  before_action :set_answer, only: [:new, :confirm, :create]

  private

  def protect_csrf?
    false
  end

  def check_release_state
    raise "404" unless @cur_node.public?
  end

  def check_reception_state
    raise "404" unless @cur_node.reception_enabled?
  end

  def check_aggregation_state
    raise "404" unless @cur_node.aggregation_enabled?
  end

  def set_columns
    disable_upload_file = {}
    disable_upload_file = { :input_type.ne => 'upload_file' } if Mongoid::Config.clients[:default_post]

    @columns = Inquiry::Column.site(@cur_site).
      where(node_id: @cur_node.id, state: "public").
      where(disable_upload_file).
      order_by(order: 1)
  end

  def set_answer
    @items = []
    @data = {}
    @to = [@cur_node.notice_email]
    @columns.each do |column|
      param = params[:item].try(:[], column.id.to_s)
      if column.input_type == "upload_file" &&
         !param.blank? &&
         !param.kind_of?(ActionDispatch::Http::UploadedFile)
        param = SS::File.with(client: Inquiry::Answer.client_name).find(param)
      end
      @items << [column, param]
      @data[column.id] = [param]
      if (column.input_type == 'text_field' || column.input_type == 'text_area') && column.transfers.present? && param.present?
        column.transfers.each do |transfer|
          @to.push(transfer[:email]) if param.include?(transfer[:keyword])
        end
      end
      if column.input_confirm == "enabled"
        @items.last << params[:item].try(:[], "#{column.id}_confirm")
        @data[column.id] << params[:item].try(:[], "#{column.id}_confirm")
      end
    end
    @to = @to.uniq.compact.sort
    @answer = Inquiry::Answer.new(cur_site: @cur_site, cur_node: @cur_node)
    @answer.remote_addr = request.env["HTTP_X_REAL_IP"] || request.remote_ip
    @answer.user_agent = request.user_agent
    @answer.source_url = params[:item].try(:[], :source_url)
    @answer.set_data(@data)
  end

  public

  def new
    #
  end

  def confirm
    if !@answer.valid?
      render action: :new
    end
  end

  def create
    if !@answer.valid? || params[:submit].blank?
      render action: :new
      return
    end

    if @cur_node.captcha_enabled?
      @answer.captcha = params[:answer].try(:[], :captcha)
      @answer.captcha_key = params[:answer].try(:[], :captcha_key)
      unless @answer.valid_with_captcha?
        render action: :confirm
        return
      end
    end

    @answer.save
    if @cur_node.notify_mail_enabled?
      @to.each { |notice_email| Inquiry::Mailer.notify_mail(@cur_site, @cur_node, @answer, notice_email).deliver_now }
    end
    if @cur_node.reply_mail_enabled?
      # `try` method doesn't work as you think because mail is an instance of Delegator.
      # see: http://tech.misoca.jp/entry/2015/12/04/110000
      mail = Inquiry::Mailer.reply_mail(@cur_site, @cur_node, @answer)
      mail.deliver_now if mail.present?
    end

    query = {}
    if @answer.source_url.present?
      if params[:preview]
        query[:ref] = view_context.cms_preview_path(site: @cur_site, path: @answer.source_content.filename)
      else
        query[:ref] = @answer.source_url
      end
    end
    query = query.to_query

    url = "#{@cur_node.url}sent.html"
    url = "#{url}?#{query}" if query.present?
    redirect_to url
  end

  def sent
    render action: :sent
  end

  def results
    @cur_node.name = "#{@cur_node.name}　#{I18n.t("inquiry.result")}"
    @aggregation = @cur_node.aggregate_select_columns
    render action: :results
  end
end
