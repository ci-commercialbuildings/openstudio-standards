class Standard
  def model_add_hvac(model, building_type, climate_zone, prototype_input, epw_file)

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Started Adding HVAC')

    # Get the list of HVAC systems, as defined for each building in the Prototype.building_name files

    # Add each HVAC system
    @system_to_space_map.each do |system|
      thermal_zones = model_get_zones_from_spaces_on_system(model, system)
      return_plenum = model_get_return_plenum_from_system(model, system)

      # Add the HVAC systems
      case system['type']
      when 'VAV'
        # Retrieve the existing hot water loop or add a new one if necessary.
        hot_water_loop = nil
        hot_water_loop = if model.getPlantLoopByName('Hot Water Loop').is_initialized
                           model.getPlantLoopByName('Hot Water Loop').get
                         else
                           model_add_hw_loop(model,
                                             'NaturalGas',
                                             dsgn_sup_wtr_temp: system['hot_water_design_supply_water_temperature'],
                                             boiler_lvg_temp_dsgn: system['boiler_leaving_temperature_design'],
                                             boiler_out_temp_lmt: system['boiler_outlet_temperature_limit'],
                                             boiler_sizing_factor: system['boiler_sizing_factor'])
                         end

        # Retrieve the existing chilled water loop or add a new one if necessary.
        chilled_water_loop = nil
        if model.getPlantLoopByName('Chilled Water Loop').is_initialized
          chilled_water_loop = model.getPlantLoopByName('Chilled Water Loop').get
        else
          condenser_water_loop = nil
          if system['chiller_cooling_type'] == 'WaterCooled'
            condenser_water_loop = model_add_cw_loop(model,
                                                     cooling_tower_type: 'Open Cooling Tower',
                                                     cooling_tower_fan_type: 'Centrifugal',
                                                     cooling_tower_capacity_control: 'Fan Cycling',
                                                     number_of_cells_per_tower: 2,
                                                     number_cooling_towers: 1)
          end
          chilled_water_loop = model_add_chw_loop(model,
                                                  cooling_fuel: 'Electricity',
                                                  dsgn_sup_wtr_temp: system['chilled_water_design_supply_water_temperature'],
                                                  dsgn_sup_wtr_temp_delt: system['chilled_water_design_supply_water_temperature_delta'],
                                                  chw_pumping_type: system['chw_pumping_type'],
                                                  chiller_cooling_type: system['chiller_cooling_type'],
                                                  chiller_condenser_type: system['chiller_condenser_type'],
                                                  chiller_compressor_type: system['chiller_compressor_type'],
                                                  condenser_water_loop: condenser_water_loop)
        end

        # Add the VAV
        model_add_vav_reheat(model,
                             thermal_zones,
                             system_name: system['name'],
                             return_plenum: return_plenum,
                             reheat_type: 'Water',
                             hot_water_loop: hot_water_loop,
                             chilled_water_loop: chilled_water_loop,
                             hvac_op_sch: system['operation_schedule'],
                             oa_damper_sch: system['oa_damper_schedule'],
                             fan_efficiency: 0.62,
                             fan_motor_efficiency: 0.9,
                             fan_pressure_rise: 4.0,
                             min_sys_airflow_ratio: system['min_sys_airflow_ratio'],
                             vav_sizing_option: system['vav_sizing_option'])

      when 'CAV'
        # Retrieve the existing hot water loop or add a new one if necessary.
        hot_water_loop = nil
        hot_water_loop = if model.getPlantLoopByName('Hot Water Loop').is_initialized
                           model.getPlantLoopByName('Hot Water Loop').get
                         else
                           model_add_hw_loop(model, 'NaturalGas')
                         end

        chilled_water_loop = nil
        if model.getPlantLoopByName('Chilled Water Loop').is_initialized
          chilled_water_loop = model.getPlantLoopByName('Chilled Water Loop').get
        elsif building_type == 'Hospital'
          condenser_water_loop = nil
          condenser_water_loop = model_add_cw_loop(model) if system['chiller_cooling_type'] == 'WaterCooled'
          chilled_water_loop = model_add_chw_loop(model,
                                                  cooling_fuel: 'Electricity',
                                                  dsgn_sup_wtr_temp: system['chilled_water_design_supply_water_temperature'],
                                                  dsgn_sup_wtr_temp_delt: system['chilled_water_design_supply_water_temperature_delta'],
                                                  chw_pumping_type: system['chw_pumping_type'],
                                                  chiller_cooling_type: system['chiller_cooling_type'],
                                                  chiller_condenser_type: system['chiller_condenser_type'],
                                                  chiller_compressor_type: system['chiller_compressor_type'],
                                                  condenser_water_loop: condenser_water_loop)
        end

        # Add the CAV
        model_add_cav(model,
                      thermal_zones,
                      system_name: system['name'],
                      hot_water_loop: hot_water_loop,
                      chilled_water_loop: chilled_water_loop,
                      hvac_op_sch: system['operation_schedule'],
                      oa_damper_sch: system['oa_damper_schedule'],
                      fan_efficiency: 0.62,
                      fan_motor_efficiency: 0.9,
                      fan_pressure_rise: 4.0)

      when 'PSZ-AC'
        # Special logic to make unitary heat pumps all blow-through
        fan_position = 'DrawThrough'
        if system['heating_type'] == 'Single Speed Heat Pump' ||
           system['heating_type'] == 'Water To Air Heat Pump'
          fan_position = 'BlowThrough'
        end

        # Special logic to make a heat pump loop if necessary
        heat_pump_loop = nil
        if system['heating_type'] == 'Water To Air Heat Pump'
          heat_pump_loop = model_add_hp_loop(model)
        end

        model_add_psz_ac(model,
                         thermal_zones,
                         system_name: system['name'],
                         cooling_type: system['cooling_type'],
                         chilled_water_loop: heat_pump_loop,
                         heating_type: system['heating_type'],
                         supplemental_heating_type: system['supplemental_heating_type'],
                         hot_water_loop: heat_pump_loop,
                         fan_location: fan_position,
                         fan_type: system['fan_type'],
                         hvac_op_sch: system['operation_schedule'],
                         oa_damper_sch: system['oa_damper_schedule'])

      when 'PVAV'
        # Retrieve the existing hot water loop or add a new one if necessary.
        hot_water_loop = nil
        hot_water_loop = if model.getPlantLoopByName('Hot Water Loop').is_initialized
                           model.getPlantLoopByName('Hot Water Loop').get
                         elsif building_type == 'MediumOffice'
                           nil
                         else
                           model_add_hw_loop(model,
                                             'NaturalGas',
                                             pump_spd_ctrl: system['hotwater_pump_speed_control'])
                         end
        case system['electric_reheat']
        when true
          electric_reheat = true
        else
          electric_reheat = false
        end
        model_add_pvav(model,
                       thermal_zones,
                       system_name: system['name'],
                       hvac_op_sch: system['operation_schedule'],
                       oa_damper_sch: system['oa_damper_schedule'],
                       electric_reheat: electric_reheat,
                       hot_water_loop: hot_water_loop,
                       return_plenum: return_plenum)

      when 'DOAS Cold Supply'
        # Retrieve the existing hot water loop or add a new one if necessary.
        hot_water_loop = nil
        hot_water_loop = if model.getPlantLoopByName('Hot Water Loop').is_initialized
                           model.getPlantLoopByName('Hot Water Loop').get
                         else
                           model_add_hw_loop(model, 'NaturalGas')
                         end

        # Retrieve the existing chilled water loop or add a new one if necessary.
        chilled_water_loop = nil
        if model.getPlantLoopByName('Chilled Water Loop').is_initialized
          chilled_water_loop = model.getPlantLoopByName('Chilled Water Loop').get
        else
          condenser_water_loop = nil
          if system['chiller_cooling_type'] == 'WaterCooled'
            condenser_water_loop = model_add_cw_loop(model,
                                                     cooling_tower_type: 'Open Cooling Tower',
                                                     cooling_tower_fan_type: 'Centrifugal',
                                                     cooling_tower_capacity_control: 'Fan Cycling',
                                                     number_of_cells_per_tower: 2,
                                                     number_cooling_towers: 1)
          end
          chilled_water_loop = model_add_chw_loop(model,
                                                  cooling_fuel: 'Electricity',
                                                  dsgn_sup_wtr_temp: system['chilled_water_design_supply_water_temperature'],
                                                  dsgn_sup_wtr_temp_delt: system['chilled_water_design_supply_water_temperature_delta'],
                                                  chw_pumping_type: system['chw_pumping_type'],
                                                  chiller_cooling_type: system['chiller_cooling_type'],
                                                  chiller_condenser_type: system['chiller_condenser_type'],
                                                  chiller_compressor_type: system['chiller_compressor_type'],
                                                  condenser_water_loop: condenser_water_loop)
        end
        model_add_doas_cold_supply(model,
                                   thermal_zones,
                                   system_name: system['name'],
                                   hot_water_loop: hot_water_loop,
                                   chilled_water_loop: chilled_water_loop,
                                   hvac_op_sch: system['operation_schedule'],
                                   min_oa_sch: system['oa_damper_schedule'],
                                   min_frac_oa_sch: system['minimum_fraction_of_outdoor_air_schedule'],
                                   fan_maximum_flow_rate: system['fan_maximum_flow_rate'],
                                   econo_ctrl_mthd: system['economizer_control_method'],
                                   doas_control_strategy: system['doas_control_strategy'],
                                   clg_dsgn_sup_air_temp: system['cooling_design_supply_air_temperature'],
                                   htg_dsgn_sup_air_temp: system['heating_design_supply_air_temperature'])

        model_add_four_pipe_fan_coil(model,
                                     thermal_zones,
                                     chilled_water_loop,
                                     hot_water_loop: hot_water_loop,
                                     ventilation: false)

      when 'DC' # Data Center
        # Retrieve the existing hot water loop
        # or add a new one if necessary.
        hot_water_loop = nil
        hot_water_loop = if model.getPlantLoopByName('Hot Water Loop').is_initialized
                           model.getPlantLoopByName('Hot Water Loop').get
                         else
                           model_add_hw_loop(model, 'NaturalGas')
                         end

        # Retrieve the existing heat pump loop or add a new one if necessary.
        heat_pump_loop = if model.getPlantLoopByName('Heat Pump Loop').is_initialized
                           model.getPlantLoopByName('Heat Pump Loop').get
                         else
                           model_add_hp_loop(model)
                         end
        model_add_data_center_hvac(model,
                                   thermal_zones,
                                   hot_water_loop,
                                   heat_pump_loop,
                                   hvac_op_sch: system['flow_fraction_schedule'],
                                   oa_damper_sch: system['flow_fraction_schedule'],
                                   main_data_center: system['main_data_center'])

      when 'SAC'
        model_add_split_ac(model,
                           thermal_zones,
                           cooling_type: system['cooling_type'],
                           heating_type: system['heating_type'],
                           supplemental_heating_type: system['supplemental_heating_type'],
                           fan_type: system['fan_type'],
                           hvac_op_sch: system['operation_schedule'],
                           oa_damper_sch: system['oa_damper_schedule'],
                           econ_max_oa_frac_sch: system['econ_max_oa_frac_sch'])

      when 'UnitHeater'
        model_add_unitheater(model,
                             thermal_zones,
                             hvac_op_sch: system['operation_schedule'],
                             fan_control_type: system['fan_type'],
                             fan_pressure_rise: system['fan_static_pressure'],
                             heating_type: system['heating_type'])

      when 'PTAC'
        model_add_ptac(model,
                       thermal_zones,
                       cooling_type: system['cooling_type'],
                       heating_type: system['heating_type'],
                       fan_type: system['fan_type'])

      when 'PTHP'
          model_add_pthp(model,
                         thermal_zones,
                         fan_type: system['fan_type'])

      when 'Exhaust Fan'
        model_add_exhaust_fan(model,
                              thermal_zones,
                              flow_rate: system['flow_rate'],
                              availability_sch_name: system['operation_schedule'],
                              flow_fraction_schedule_name: system['flow_fraction_schedule'],
                              balanced_exhaust_fraction_schedule_name: system['balanced_exhaust_fraction_schedule'])

      when 'Zone Ventilation'
        model_add_zone_ventilation(model,
                                   thermal_zones,
                                   ventilation_type: system['ventilation_type'],
                                   flow_rate: system['flow_rate'],
                                   availability_sch_name: system['operation_schedule'])

      when 'Refrigeration'
        model_add_refrigeration(model,
                                system['case_type'],
                                system['cooling_capacity_per_length'],
                                system['length'],
                                system['evaporator_fan_pwr_per_length'],
                                system['lighting_per_length'],
                                system['lighting_schedule'],
                                system['defrost_pwr_per_length'],
                                system['restocking_schedule'],
                                system['cop'],
                                system['cop_f_of_t_curve_name'],
                                system['condenser_fan_pwr'],
                                system['condenser_fan_pwr_curve_name'],
                                thermal_zones[0])

      # When multiple cases and walk-ins asssigned to a system
      when 'Refrigeration_system'
        model_add_refrigeration_system(model,
                                       system['compressor_type'],
                                       system['name'],
                                       system['cases'],
                                       system['walkins'],
                                       thermal_zones[0])

      when 'WSHP'
        condenser_loop = case system['heating_type']
                         when 'Gas'
                           model_get_or_add_heat_pump_loop(model)
                         else
                           model_get_or_add_ambient_water_loop(model)
                         end
        model_add_water_source_hp(model,
                                  thermal_zones,
                                  condenser_loop,
                                  ventilation:true)

      when 'Fan Coil'
        case system['heating_type']
        when 'Gas', 'DistrictHeating', 'Electricity'
          hot_water_loop = model_get_or_add_hot_water_loop(model, system['heating_type'])
        when nil
          hot_water_loop = nil
        end
        case system['cooling_type']
        when 'Electricity', 'DistrictCooling'
          chilled_water_loop = model_get_or_add_chilled_water_loop(model, system['cooling_type'], chilled_water_loop_cooling_type: 'AirCooled')
        when nil
          chilled_water_loop = nil
        end
        model_add_four_pipe_fan_coil(model,
                                     thermal_zones,
                                     chilled_water_loop,
                                     hot_water_loop: hot_water_loop,
                                     ventilation: true)

      when 'Baseboards'
        case system['heating_type']
        when 'Gas', 'DistrictHeating'
          hot_water_loop = model_get_or_add_hot_water_loop(model, main_heat_fuel)
        when 'Electricity'
          hot_water_loop = nil
        when nil
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "Baseboards must have heating_type specified.")
        end
        model_add_baseboard(model,
                            thermal_zones,
                            hot_water_loop: hot_water_loop)

      when 'Unconditioned'
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "System type is Unconditioned.  No system will be added.")

      else
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "System type '#{system['type']}' is not recognized for system named '#{system['name']}'.  This system will not be added.")

      end
    end

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "Finished adding HVAC")

    return true
  end # add hvac

  private

  def model_get_zones_from_spaces_on_system(model, system)
    # Find all zones associated with these spaces
    thermal_zones = []
    system['space_names'].each do |space_name|
      space = model.getSpaceByName(space_name)
      if space.empty?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "No space called #{space_name} was found in the model, cannot be added to HVAC system.")
        next
      end
      space = space.get
      zone = space.thermalZone
      if zone.empty?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "Space #{space_name} has no thermal zone; cannot add an HVAC system to this space.")
        next
      end
      thermal_zones << zone.get
    end

    return thermal_zones
  end

  def model_get_return_plenum_from_system(model, system)
    # Find the zone associated with the return plenum space name
    return_plenum = nil

    # Return nil if no return plenum
    return return_plenum if system['return_plenum'].nil?

    # Get the space
    space = model.getSpaceByName(system['return_plenum'])
    if space.empty?
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "No space called #{system['return_plenum']} was found in the model, cannot be a return plenum.")
      return return_plenum
    end
    space = space.get

    # Get the space's zone
    zone = space.thermalZone
    if zone.empty?
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "Space #{space.name} has no thermal zone; cannot be a return plenum.")
      return return_plenum
    end

    return zone.get
  end
end
