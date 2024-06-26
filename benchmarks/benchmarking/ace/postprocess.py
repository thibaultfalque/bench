import loguru
import yaml
import sys
import tempfile
import os 
import pathlib
from metrics.wallet import BasicAnalysis

if __name__=="__main__":
  if len(sys.argv)!=2:
    loguru.logger.error("Usage: python postprocess.py <path_to_campaign>")
    sys.exit(1)
  loguru.logger.info("Starting postprocessing....")
  with open(os.path.join(pathlib.Path(__file__).parent.resolve(),'postprocess_config.yml'), 'r') as stream:
    try:
      config = yaml.safe_load(stream)
      config["source"]["path"]=sys.argv[1]
      with tempfile.NamedTemporaryFile(delete=False,mode="w",suffix=".yaml") as tmp:
        yaml.dump(config, tmp)
        my_campaign = BasicAnalysis(input_file=tmp.name, log_level='INFO')
        df = my_campaign.data_frame
        df["configuration"] = df.apply(lambda x: x["experiment_ware"]+"_"+x["input"], axis=1)
        df["problem"] = df["input"].apply(lambda x: x.split("-")[0])
        df["model"]=df["input"].values
        df["time"]=df["cpu_time"].values
        df["method"]=df["method"].apply(lambda x: "minimize" if x=="min" else  ("maximize" if x=='max' else x)) 
        campaign_name = sys.argv[1].split("/")[-2]
        stat_df = df[["configuration","problem","model","status","time","cores","threads","datetime","failures","propagations","method","solutions","objective"]]
        loguru.logger.info(f"Writing statistics to csv: {sys.argv[1]}/../{campaign_name}.csv")
        stat_df.to_csv(f"{sys.argv[1]}/../{campaign_name}.csv",index=False)
        obj_df = df[["configuration","problem","model","time","objective"]]
        loguru.logger.info(f"Writing objectives to csv: {sys.argv[1]}/../{campaign_name}-objectives.csv") 
        obj_df.to_csv(f"{sys.argv[1]}/../{campaign_name}-objectives.csv",index=False)

    except yaml.YAMLError as exc:
      loguru.logger.error(exc)
  