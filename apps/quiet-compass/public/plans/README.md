# Official venue plan previews

Retrieved October 24, 2026. These PNGs render the first page of the operator's PDF at a maximum dimension of 1,800 pixels. They are not generated floor plans, acoustic measurements or verified routes. The app links to the original full PDF and operator page. Copyright remains with the respective source owners.

| Preview | Official document | Scope |
| --- | --- | --- |
| `moscone-lobby.png` | https://www.moscone.com/sites/default/files/floor_plans/pdf/MCNS-Lobby%20Level_20240430%20full%20set.pdf | North/South lobby level, drawing dated April 30, 2024; first of 8 pages |
| `gallery-308.png` | https://fortmason.org/wp-content/uploads/2025/12/Floorplan.pdf | Gallery 308 only; one page; drawing date not confirmed |
| `yerba-buena.png` | https://yerbabuenagardens.org/wp-content/uploads/2025/10/ADA-Map-Oct-2025.pdf | Outdoor accessibility map, October 2025; one page |

Render using `pdftoppm -f 1 -singlefile -scale-to 1800 -png SOURCE.pdf OUTPUT_STEM`. Keep labels, legends, restricted-access markings and source framing intact.
