# Copyright 2011, Keith Hudgins 
# 
# Licensed under the Apache License, Version 2.0 (the "License"); 
# you may not use this file except in compliance with the License. 
# You may obtain a copy of the License at 
# 
#  http://www.apache.org/licenses/LICENSE-2.0 
# 
# Unless required by applicable law or agreed to in writing, software 
# distributed under the License is distributed on an "AS IS" BASIS, 
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. 
# See the License for the specific language governing permissions and 
# limitations under the License. 
# 

class ZenossService < ServiceObject

  def initialize(thelogger)
    @bc_name = "zenoss"
    @logger = thelogger
  end
  
  #if barclamp allows multiple proposals OVERRIDE
  # def self.allow_multiple_proposals?
  
  def create_proposal
    @logger.debug("Zenoss create_proposal: entering")
    base = super

    nodes = NodeObject.all
    nodes.delete_if { |n| n.nil? or n.admin? }
    if nodes.size >= 1
      base["deployment"]["zenoss"]["elements"] = {
        "zenoss-server" => [ nodes.first[:fqdn] ]
      }
    end

    @logger.debug("Zenoss create_proposal: exiting")
    base
  end
  
  # Note by Keith:
  # This transition method is COMPLETELY UNTESTED!!
  # It's some boilerplate code moved over from the Nagios barclamp and very lightly
  # converted (search and replace, really). If you wanna test this, get your zenoss server
  # node running and then start launching new nodes to confirm.
  
  def transition(inst, name, state)
      @logger.debug("Zenoss transition: make sure that network role is on all nodes: #{name} for #{state}")

      #
      # If we are discovering the node, make sure that we add the zenoss client or server to the node
      #
      if state == "discovered"
        @logger.debug("Zenoss transition: discovered state for #{name} for #{state}")
        db = ProposalObject.find_proposal "zenoss", inst
        role = RoleObject.find_role_by_name "zenoss-config-#{inst}"

        if role.override_attributes["zenoss"]["elements"]["zenoss-server"].nil? or
           role.override_attributes["zenoss"]["elements"]["zenoss-server"].empty?
          @logger.debug("Zenoss transition: make sure that zenoss-server role is on first: #{name} for #{state}")
          result = add_role_to_instance_and_node("zenoss", inst, name, db, role, "zenoss-server")
        else
          node = NodeObject.find_node_by_name name
          unless node.role? "zenoss-server"
            @logger.debug("Zenoss transition: make sure that zenoss-client role is on all nodes but first: #{name} for #{state}")
            result = add_role_to_instance_and_node("zenoss", inst, name, db, role, "zenoss-client")
          else
            result = true
          end
        end

        # Set up the client url
        if result
          role = RoleObject.find_role_by_name "zenoss-config-#{inst}"

          # Get the server IP address
          server_ip = nil
          [ "zenoss-server" ].each do |element|
            tnodes = role.override_attributes["zenoss"]["elements"][element]
            next if tnodes.nil? or tnodes.empty?
            tnodes.each do |n|
              next if n.nil?
              node = NodeObject.find_node_by_name(n)
              server_ip = node.get_network_by_type("admin")["address"]
            end
          end

          # Any specific attributes that need to be handed off to clients form the server can be injected in this stanza:
          # The stuff that's already here is probably nagios specific and should be changed.
          unless server_ip.nil?
            node = NodeObject.find_node_by_name(name)
            node.crowbar["crowbar"] = {} if node.crowbar["crowbar"].nil?
            node.crowbar["crowbar"]["links"] = {} if node.crowbar["crowbar"]["links"].nil?
            #node.crowbar["crowbar"]["links"]["Nagios"] = "http://#{server_ip}/nagios3/cgi-bin/extinfo.cgi?type=1&host=#{node.shortname}"
            node.save
          end 
        end

        @logger.debug("Zenoss transition: leaving from discovered state for #{name} for #{state}")
        a = [200, NodeObject.find_node_by_name(name).to_hash ] if result
        a = [400, "Failed to add role to node"] unless result
        return a
      end

      @logger.debug("Zenoss transition: leaving for #{name} for #{state}")
      [200, NodeObject.find_node_by_name(name).to_hash ]
    end

  def apply_role_pre_chef_call(old_role, role, all_nodes)
    @logger.debug("Zenoss apply_role_pre_chef_call: entering #{all_nodes.inspect}")
    return if all_nodes.empty?

    # Make sure the bind hosts are in the admin network
    all_nodes.each do |n|
      node = NodeObject.find_node_by_name n

      admin_address = node.get_network_by_type("admin")["address"]
      node.crowbar[:zenoss] = {} if node.crowbar[:zenoss].nil?
      node.crowbar[:zenoss][:api_bind_host] = admin_address

      node.save
    end
    @logger.debug("Zenoss apply_role_pre_chef_call: leaving")
  end

end

