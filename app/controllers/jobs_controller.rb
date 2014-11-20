require 'base64'

class JobsController < ApplicationController

  prepend_before_action do
    if(params[:job_id])
      params[:account_id] = Job.find(params[:job_id]).try(:account_id)
    end
  end

  before_action do
    @valid_jobs = Job.dataset.join_table(:left, :jobs___j2){ |j2, j| ({Sequel.qualify(j, :message_id) => Sequel.qualify(j2, :message_id)}) & (Sequel.qualify(j, :created_at) < Sequel.qualify(j2, :created_at))}.where(:j2__id => nil).select(:jobs__id)
    @product = Product.find_by_internal_name(params[:namespace])
    @jobs_complete = Job.dataset_with_complete.where(
      :account_id => @accounts.map(&:id)
    ).where('? = ANY(complete)', params[:namespace].to_s)
    @jobs_inprogress = Job.dataset_with_router.where(
      :account_id => @accounts.map(&:id)
    ).where('? = ANY(router)', params[:namespace].to_s)
    @jobs_error = Job.dataset_with(
      :scalars => {
        :error => ['error', 'callback']
      }
    ).where("error like ?", "#{params[:namespace]}:%")
    if(params[:payload_filter])
      location = MultiJson.load(Base64.urlsafe_decode64(params[:payload_filter]))
      value = Base64.urlsafe_decode64(params[:payload_value])
      @jobs_inprogress = Job.dataset_with(
        :scalars => {
          :custom_search => location
        }
      ).where(:id => @jobs_inprogress.select(:id)).
        where(:custom_search => value)
      @jobs_complete = Job.dataset_with(
        :scalars => {
          :custom_search => location
        }
      ).where(:id => @jobs_complete.select(:id)).
        where(:custom_search => value)
    end
  end

  ## Need success and error counts
  # -> query for error payloads
  # -> subtract/remove from completed depending on view
  # -> need to add group by and squash so we showing jobs and not
  #counting history


  def all
    respond_to do |format|
      format.js do
        flash[:error] = 'Unsupported request!'
        javascript_redirect_to dashboard_path
      end
      format.html do
        complete_jobs = @jobs_complete.select(:id).all.map(&:id) + @jobs_inprogress.select(:id).all.map(&:id) + @jobs_error.select(:id).all.map(&:id)
        @jobs = Job.where(:id => @valid_jobs).where(:id => complete_jobs).all
        @progress = (@jobs.map(&:percent_complete).sum.to_f / @jobs.count)
        @data = Hash[
          @accounts.map do |acct|
            [
              acct,
              Smash.new(
                :in_progress => @jobs_inprogress.where(:id => @valid_jobs, :account_id => acct.id).all,
                :completed => @jobs_complete.where(:id => @valid_jobs, :account_id => acct.id).all
              )
            ]
          end
        ]
      end
    end
  end

  def list
  end

  def details
  end



  def index
    respond_to do |format|
      format.js do
        flash[:error] = 'Unsupported request!'
        if(@account)
          javascript_redirect_to account_jobs_path(@account)
        else
          javascript_redirect_to jobs_path
        end
      end
      format.html do
        @jobs = @jobs.order(:created_at.desc).paginate(page, per_page)
        enable_pagination_on(@jobs)
      end
    end
  end

  def show
    respond_to do |format|
      format.js do
        flash[:error] = 'Unsupported request!'
        if(@account)
          javascript_redirect_to account_jobs_path(@account)
        else
          javascript_redirect_to jobs_path
        end
      end
      format.html do
        @job = @jobs.where(:id => params[:id]).first
        @history = @jobs.where(:message_id => @job.message_id).order(:created_at.desc)
        unless(@job)
          if(@account)
            javascript_redirect_to account_jobs_path(@account)
          else
            javascript_redirect_to jobs_path
          end
        end
      end
    end
  end

end