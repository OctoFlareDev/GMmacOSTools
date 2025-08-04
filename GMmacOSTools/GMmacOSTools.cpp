//
//  GMmacOSTools.cpp
//  GMmacOSTools
//
//  Created by Flare ​ on 8/4/25.
//

#include <iostream>
#include "GMmacOSTools.hpp"
#include "GMmacOSToolsPriv.hpp"

void GMmacOSTools::HelloWorld(const char * s)
{
    GMmacOSToolsPriv *theObj = new GMmacOSToolsPriv;
    theObj->HelloWorldPriv(s);
    delete theObj;
};

void GMmacOSToolsPriv::HelloWorldPriv(const char * s) 
{
    std::cout << s << std::endl;
};

