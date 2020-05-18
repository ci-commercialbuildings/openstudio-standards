require_relative '../helpers/minitest_helper'
require_relative '../helpers/create_doe_prototype_helper'

class DOEPrototypeBaseline < CreateDOEPrototypeBuildingTest

  def self.generate_prototype_model_and_baseline(building_type, template, climate_zone, hvac_building_type = 'All others', wwr_building_type = 'All others', swh_building_type = 'All others')
      # Initialize weather file, necessary but not used
      epw_file = 'USA_FL_Miami.Intl.AP.722020_TMY3.epw'

      # Create output folder if it doesn't already exist
      @test_dir = "#{Dir.pwd}/output"
      if !Dir.exists?(@test_dir)
        Dir.mkdir(@test_dir)
      end

      # Define model name and run folder if it doesn't already exist,
      # if it does, remove it and re-create it.
      model_name = "#{building_type}-#{template}-#{climate_zone}"
      run_dir = "#{@test_dir}/#{model_name}"
      if !Dir.exists?(run_dir)
        Dir.mkdir(run_dir)
      else
        FileUtils.rm_rf(run_dir)
        Dir.mkdir(run_dir)
      end
      run_dir_baseline = "#{run_dir}-Baseline"
      if Dir.exists?(run_dir_baseline)
        FileUtils.rm_rf(run_dir_baseline)
      end

      # Create the prototype
      prototype_creator = Standard.build("#{template}_#{building_type}")
      model = prototype_creator.model_create_prototype_model(climate_zone, epw_file, run_dir)

      # Save prototype OSM file
      osm_path = OpenStudio::Path.new("#{run_dir}/#{model_name}.osm")
      model.save(osm_path, true)

      # Translate prototype model to an IDF file
      forward_translator = OpenStudio::EnergyPlus::ForwardTranslator.new
      idf_path = OpenStudio::Path.new("#{run_dir}/#{model_name}.idf")
      idf = forward_translator.translateModel(model)
      idf.save(idf_path,true)

      # Initialize 90.1-2019 PRM Standard class
      prototype_creator = Standard.build("90.1-PRM-2019")

      # Create baseline model
      model_baseline = prototype_creator.model_create_prm_stable_baseline_building(model, building_type, climate_zone, hvac_building_type, wwr_building_type, swh_building_type, nil, run_dir_baseline, false)
      return model_baseline, model
    end

  def test_create_prototype_baseline_building
      # Define prototypes to be generated
      @templates = ['90.1-2013']
      @building_types = ['MidriseApartment']
      @climate_zones = ['ASHRAE 169-2013-2A']

      # Generate prototype building models and associated baselines
      all_comp =  @building_types.product @templates, @climate_zones
      all_comp.each do |building_type, template, climate_zone|
        model_baseline, model = DOEPrototypeBaseline.generate_prototype_model_and_baseline(building_type, template, climate_zone, 'All others', 'Office <= 5,000 sq ft', 'All others')
        assert(model_baseline,"Baseline model could not be generated for #{building_type}, #{template}, #{climate_zone}.")

        # Load baseline model
        @test_dir = "#{Dir.pwd}/output"
        model_baseline = OpenStudio::Model::Model.load("#{@test_dir}/#{building_type}-#{template}-#{climate_zone}-Baseline/final.osm")
        model_baseline = model_baseline.get

        # Do sizing run for baseline model
        prototype_creator = Standard.build("90.1-PRM-2019")
        sim_control = model_baseline.getSimulationControl
        sim_control.setRunSimulationforSizingPeriods(true)
        sim_control.setRunSimulationforWeatherFileRunPeriods(false)
        baseline_run = prototype_creator.model_run_simulation_and_log_errors(model_baseline, "#{@test_dir}/#{building_type}-#{template}-#{climate_zone}-Baseline/SR1")

        # Check that proposed sizing ran
        assert(File.file?("#{@test_dir}/#{building_type}-#{template}-#{climate_zone}-Baseline/SR_PROP/run/eplusout.sql"), "The #{building_type}, #{template}, #{climate_zone} proposed model sizing run did not run.")
 
        # Check IsResidential for MidRiseApartment
        # Determine whether any space is residential
        has_res = false
        model_baseline.getSpaces.sort.each do |space|
          if space_residential?(space)
            has_res = true
          end
        end
        has_res_goal = true
        assert(has_res == has_res_goal, "Failure to set space_residential? for #{building_type}, #{template}, #{climate_zone}.")

      end
  end
end