class ProductController < ApplicationController

  protect_from_forgery :only => [:update, :destroy]

  def index
    @products = Product.all
    @prod = Product.new
  end

  def create
    p = Product.new(params[:prod])
    XMPP.send_message_all "Created product: #{p.name}"
    p.created_at = Time.now
    p.updated_at = Time.now
    p.save
    redirect_to url_for(:action => 'index')
  end

  def delete
    p = Product.find(params[:id])
    XMPP.send_message_all "Removed product: #{p.name}"
    Product.delete(params[:id])
    redirect_to url_for(:action => 'index')
  end

end
