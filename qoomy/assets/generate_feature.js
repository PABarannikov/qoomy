const puppeteer = require('puppeteer');
const path = require('path');

async function generateFeatureGraphic() {
    const browser = await puppeteer.launch();
    const page = await browser.newPage();

    await page.setViewport({ width: 1024, height: 500 });

    const htmlPath = path.join(__dirname, 'feature_template.html');
    await page.goto('file://' + htmlPath);

    await page.screenshot({
        path: path.join(__dirname, 'feature_graphic.png'),
        type: 'png'
    });

    await browser.close();
    console.log('Feature graphic created successfully!');
}

generateFeatureGraphic();
