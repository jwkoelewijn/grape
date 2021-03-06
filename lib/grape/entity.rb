require 'hashie'

module Grape
  # An Entity is a lightweight structure that allows you to easily 
  # represent data from your application in a consistent and abstracted
  # way in your API.
  #
  # @example Entity Definition
  #
  #   module API
  #     module Entities
  #       class User < Grape::Endpoint
  #         expose :first_name, :last_name, :screen_name, :location
  #         expose :latest_status, :using => API::Status, :as => :status, :unless => {:collection => true}
  #         expose :email, :if => {:type => :full}
  #         expose :new_attribute, :if => {:version => 'v2'}
  #         expose(:name){|model,options| [model.first_name, model.last_name].join(' ')}
  #       end
  #     end
  #   end
  #
  # Entities are not independent structures, rather, they create 
  # **representations** of other Ruby objects using a number of methods
  # that are convenient for use in an API. Once you've defined an Entity,
  # you can use it in your API like this:
  #
  # @example Usage in the API Layer
  #
  #   module API
  #     class Users < Grape::API
  #       version 'v2'
  #
  #       get '/users' do
  #         @users = User.all
  #         type = current_user.admin? ? :full : :default
  #         present @users, :with => API::Entities::User, :type => type
  #       end
  #     end
  #   end
  class Entity
    attr_reader :object, :options

    # This method is the primary means by which you will declare what attributes
    # should be exposed by the entity.
    #
    # @option options :as Declare an alias for the representation of this attribute.
    # @option options :if When passed a Hash, the attribute will only be exposed if the
    #   runtime options match all the conditions passed in. When passed a lambda, the
    #   lambda will execute with two arguments: the object being represented and the
    #   options passed into the representation call. Return true if you want the attribute
    #   to be exposed.
    # @option options :unless When passed a Hash, the attribute will be exposed if the
    #   runtime options fail to match any of the conditions passed in. If passed a lambda,
    #   it will yield the object being represented and the options passed to the
    #   representation call. Return true to prevent exposure, false to allow it.
    # @option options :using This option allows you to map an attribute to another Grape
    #   Entity. Pass it a Grape::Entity class and the attribute in question will 
    #   automatically be transformed into a representation that will receive the same
    #   options as the parent entity when called. Note that arrays are fine here and
    #   will automatically be detected and handled appropriately.
    # @option options :proc If you pass a Proc into this option, it will
    #   be used directly to determine the value for that attribute. It
    #   will be called with the represented object as well as the
    #   runtime options that were passed in. You can also just supply a
    #   block to the expose call to achieve the same effect.
    def self.expose(*args, &block)
      options = args.last.is_a?(Hash) ? args.pop : {}

      if args.size > 1
        raise ArgumentError, "You may not use the :as option on multi-attribute exposures." if options[:as]
        raise ArgumentError, "You may not use block-setting on multi-attribute exposures." if block_given?
      end

      options[:proc] = block if block_given?

      args.each do |attribute|
        exposures[attribute.to_sym] = options
      end
    end

    # Returns a hash of exposures that have been declared for this Entity. The keys
    # are symbolized references to methods on the containing object, the values are
    # the options that were passed into expose.
    def self.exposures
      (@exposures ||= {})
    end

    # This convenience method allows you to instantiate one or more entities by
    # passing either a singular or collection of objects. Each object will be
    # initialized with the same options. If an array of objects is passed in,
    # an array of entities will be returned. If a single object is passed in,
    # a single entity will be returned.
    #
    # @param objects [Object or Array] One or more objects to be represented.
    # @param options [Hash] Options that will be passed through to each entity
    #   representation.
    def self.represent(objects, options = {})
      if objects.is_a?(Array)
        objects.map{|o| self.new(o, {:collection => true}.merge(options))}
      else
        self.new(objects, options)
      end
    end

    def initialize(object, options = {})
      @object, @options = object, options
    end

    def exposures
      self.class.exposures
    end

    # The serializable hash is the Entity's primary output. It is the transformed
    # hash for the given data model and is used as the basis for serialization to
    # JSON and other formats.
    #
    # @param options [Hash] Any options you pass in here will be known to the entity
    #   representation, this is where you can trigger things from conditional options
    #   etc.
    def serializable_hash(runtime_options = {})
      opts = options.merge(runtime_options)
      exposures.inject({}) do |output, (attribute, exposure_options)|
        output[key_for(attribute)] = value_for(attribute, opts) if conditions_met?(exposure_options, opts)
        output
      end
    end

    alias :as_json :serializable_hash

    protected

    def key_for(attribute)
      exposures[attribute.to_sym][:as] || attribute.to_sym
    end

    def value_for(attribute, options = {})
      exposure_options = exposures[attribute.to_sym]

      if exposure_options[:proc]
        exposure_options[:proc].call(object, options)
      elsif exposure_options[:using]
        exposure_options[:using].represent(object.send(attribute))
      else
        object.send(attribute)
      end
    end

    def conditions_met?(exposure_options, options)
      if_condition = exposure_options[:if]
      unless_condition = exposure_options[:unless]

      case if_condition
        when Hash; if_condition.each_pair{|k,v| return false if options[k.to_sym] != v }
        when Proc; return false unless if_condition.call(object, options)
      end

      case unless_condition
        when Hash; unless_condition.each_pair{|k,v| return false if options[k.to_sym] == v}
        when Proc; return false if unless_condition.call(object, options)
      end

      true
    end
  end
end
