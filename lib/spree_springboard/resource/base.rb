module SpreeSpringboard
  module Resource
    class Base
      attr_reader :errors

      def after_sync(_resource); end

      def client(_resource)
        raise 'Implement `client` for each resource'
      end

      def export_params(_resource)
        {}
      end

      def initialize
        @errors = []
      end

      def update(resource, params)
        response = client_update(resource).put(params)
        response && response.success?
      end

      def sync(resource)
        # Export one resource to Springboard
        # Can be used as update as well
        response = client(resource).send(sync_method(resource), export_params(resource))
        if response && response.success?
          if response.resource
            # if sync_method == post and successful then update springboard_id
            # sync_method == post doesnt return resource
            springboard_resource = response.resource.get
            resource.set_springboard_id(springboard_resource[:id])
            resource.reload
          end

          after_sync(resource)
          return resource.springboard_id
        end

        false
      end

      def sync_method(resource)
        resource.springboard_id ? :put : :post
      end

      def self.sync_parent(client_string, resource_type, resource_export_params, parent)
        # Export one resource to Springboard
        # Resource will be linked to a parent object
        # Example - customer or address for guest order
        custom_client = SpreeSpringboard.client[client_string]
        response = custom_client.post(resource_export_params)
        if response && response.success?
          springboard_resource = response.resource.get
          parent.set_child_springboard_id(resource_type, springboard_resource[:id])

          return springboard_resource[:id]
        end

        false
      end
    end
  end
end
