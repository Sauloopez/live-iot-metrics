import uPlot from "uplot";

export const ChartHook = {
  mounted() {
    console.log(this.el);
    const sensorId = this.el.dataset.sensorId;
    const rawData = JSON.parse(this.el.dataset.readings || "[]");

    this.data = [
      rawData.map((d) => Math.floor(new Date(d.time).getTime() / 1000)),
      rawData.map((d) => d.value),
    ];

    const opts = {
      id: this.el.id,
      width: this.el.offsetWidth || 400,
      height: 300,
      series: [
        {},
        {
          label: "Valor",
          stroke: "#3b82f6",
          width: 2,
        },
      ],
      axes: [{}, { grid: { show: true } }],
    };

    this.plot = new uPlot(opts, this.data, this.el);

    this.handleEvent("new-data", (payload) => {
      if (payload.sensor_id === sensorId) {
        const newTimestamp = Math.floor(
          new Date(payload.time).getTime() / 1000,
        );

        this.data[0].push(newTimestamp);
        this.data[1].push(payload.value);

        if (this.data[0].length > 50) {
          this.data[0].shift();
          this.data[1].shift();
        }

        this.plot.setData(this.data);
      }
    });
  },

  updated() {
    this.plot.setSize({
      width: this.el.offsetWidth,
      height: 300,
    });
  },
};
